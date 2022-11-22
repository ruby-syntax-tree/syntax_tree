# frozen_string_literal: true

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    # This class is meant to mirror RubyVM::InstructionSequence. It contains a
    # list of instructions along with the metadata pertaining to them. It also
    # functions as a builder for the instruction sequence.
    class InstructionSequence
      MAGIC = "YARVInstructionSequence/SimpleDataFormat"

      # This provides a handle to the rb_iseq_load function, which allows you to
      # pass a serialized iseq to Ruby and have it return a
      # RubyVM::InstructionSequence object.
      ISEQ_LOAD =
        begin
          Fiddle::Function.new(
            Fiddle::Handle::DEFAULT["rb_iseq_load"],
            [Fiddle::TYPE_VOIDP] * 3,
            Fiddle::TYPE_VOIDP
          )
        rescue NameError
        end

      # This object is used to track the size of the stack at any given time. It
      # is effectively a mini symbolic interpreter. It's necessary because when
      # instruction sequences get serialized they include a :stack_max field on
      # them. This field is used to determine how much stack space to allocate
      # for the instruction sequence.
      class Stack
        attr_reader :current_size, :maximum_size

        def initialize
          @current_size = 0
          @maximum_size = 0
        end

        def change_by(value)
          @current_size += value
          @maximum_size = @current_size if @current_size > @maximum_size
        end
      end

      # The type of the instruction sequence.
      attr_reader :type

      # The name of the instruction sequence.
      attr_reader :name

      # The parent instruction sequence, if there is one.
      attr_reader :parent_iseq

      # The location of the root node of this instruction sequence.
      attr_reader :location

      # This is the list of information about the arguments to this
      # instruction sequence.
      attr_accessor :argument_size
      attr_reader :argument_options

      # The list of instructions for this instruction sequence.
      attr_reader :insns

      # The table of local variables.
      attr_reader :local_table

      # The hash of names of instance and class variables pointing to the
      # index of their associated inline storage.
      attr_reader :inline_storages

      # The index of the next inline storage that will be created.
      attr_reader :storage_index

      # An object that will track the current size of the stack and the
      # maximum size of the stack for this instruction sequence.
      attr_reader :stack

      # These are various compilation options provided.
      attr_reader :frozen_string_literal,
                  :inline_const_cache,
                  :operands_unification,
                  :specialized_instruction

      def initialize(
        type,
        name,
        parent_iseq,
        location,
        frozen_string_literal: false,
        inline_const_cache: true,
        operands_unification: true,
        specialized_instruction: true
      )
        @type = type
        @name = name
        @parent_iseq = parent_iseq
        @location = location

        @argument_size = 0
        @argument_options = {}

        @local_table = LocalTable.new
        @inline_storages = {}
        @insns = []
        @storage_index = 0
        @stack = Stack.new

        @frozen_string_literal = frozen_string_literal
        @inline_const_cache = inline_const_cache
        @operands_unification = operands_unification
        @specialized_instruction = specialized_instruction
      end

      ##########################################################################
      # Query methods
      ##########################################################################

      def local_variable(name, level = 0)
        if (lookup = local_table.find(name, level))
          lookup
        elsif parent_iseq
          parent_iseq.local_variable(name, level + 1)
        end
      end

      def inline_storage
        storage = storage_index
        @storage_index += 1
        storage
      end

      def inline_storage_for(name)
        inline_storages[name] = inline_storage unless inline_storages.key?(name)

        inline_storages[name]
      end

      def length
        insns.inject(0) do |sum, insn|
          case insn
          when Integer, Symbol
            sum
          else
            sum + insn.length
          end
        end
      end

      def eval
        raise "Unsupported platform" if ISEQ_LOAD.nil?
        compiled = to_a

        # Temporary hack until we get these working.
        compiled[4][:node_id] = 11
        compiled[4][:node_ids] = [1, 0, 3, 2, 6, 7, 9, -1]

        Fiddle.dlunwrap(ISEQ_LOAD.call(Fiddle.dlwrap(compiled), 0, nil)).eval
      end

      def to_a
        versions = RUBY_VERSION.split(".").map(&:to_i)

        [
          MAGIC,
          versions[0],
          versions[1],
          1,
          {
            arg_size: argument_size,
            local_size: local_table.size,
            stack_max: stack.maximum_size
          },
          name,
          "<compiled>",
          "<compiled>",
          location.start_line,
          type,
          local_table.names,
          argument_options,
          [],
          insns.map do |insn|
            insn.is_a?(Integer) || insn.is_a?(Symbol) ? insn : insn.to_a(self)
          end
        ]
      end

      ##########################################################################
      # Child instruction sequence methods
      ##########################################################################

      def child_iseq(type, name, location)
        InstructionSequence.new(
          type,
          name,
          self,
          location,
          frozen_string_literal: frozen_string_literal,
          inline_const_cache: inline_const_cache,
          operands_unification: operands_unification,
          specialized_instruction: specialized_instruction
        )
      end

      def block_child_iseq(location)
        current = self
        current = current.parent_iseq while current.type == :block
        child_iseq(:block, "block in #{current.name}", location)
      end

      def class_child_iseq(name, location)
        child_iseq(:class, "<class:#{name}>", location)
      end

      def method_child_iseq(name, location)
        child_iseq(:method, name, location)
      end

      def module_child_iseq(name, location)
        child_iseq(:class, "<module:#{name}>", location)
      end

      def singleton_class_child_iseq(location)
        child_iseq(:class, "singleton class", location)
      end

      ##########################################################################
      # Instruction push methods
      ##########################################################################

      def push(insn)
        insns << insn

        case insn
        when Integer, Symbol, Array
          insn
        else
          stack.change_by(-insn.pops + insn.pushes)
          insn
        end
      end

      # This creates a new label at the current length of the instruction
      # sequence. It is used as the operand for jump instructions.
      def label
        name = :"label_#{length}"
        insns.last == name ? name : event(name)
      end

      def event(name)
        push(name)
      end

      def adjuststack(number)
        push(AdjustStack.new(number))
      end

      def anytostring
        push(AnyToString.new)
      end

      def branchif(label)
        push(BranchIf.new(label))
      end

      def branchnil(label)
        push(BranchNil.new(label))
      end

      def branchunless(label)
        push(BranchUnless.new(label))
      end

      def checkkeyword(keyword_bits_index, keyword_index)
        push(CheckKeyword.new(keyword_bits_index, keyword_index))
      end

      def checkmatch(type)
        push(CheckMatch.new(type))
      end

      def checktype(type)
        push(CheckType.new(type))
      end

      def concatarray
        push(ConcatArray.new)
      end

      def concatstrings(number)
        push(ConcatStrings.new(number))
      end

      def defined(type, name, message)
        push(Defined.new(type, name, message))
      end

      def defineclass(name, class_iseq, flags)
        push(DefineClass.new(name, class_iseq, flags))
      end

      def definemethod(name, method_iseq)
        push(DefineMethod.new(name, method_iseq))
      end

      def definesmethod(name, method_iseq)
        push(DefineSMethod.new(name, method_iseq))
      end

      def dup
        push(Dup.new)
      end

      def duparray(object)
        push(DupArray.new(object))
      end

      def duphash(object)
        push(DupHash.new(object))
      end

      def dupn(number)
        push(DupN.new(number))
      end

      def expandarray(length, flags)
        push(ExpandArray.new(length, flags))
      end

      def getblockparam(index, level)
        push(GetBlockParam.new(index, level))
      end

      def getblockparamproxy(index, level)
        push(GetBlockParamProxy.new(index, level))
      end

      def getclassvariable(name)
        if RUBY_VERSION < "3.0"
          push(Legacy::GetClassVariable.new(name))
        else
          push(GetClassVariable.new(name, inline_storage_for(name)))
        end
      end

      def getconstant(name)
        push(GetConstant.new(name))
      end

      def getglobal(name)
        push(GetGlobal.new(name))
      end

      def getinstancevariable(name)
        if RUBY_VERSION < "3.2"
          push(GetInstanceVariable.new(name, inline_storage_for(name)))
        else
          push(GetInstanceVariable.new(name, inline_storage))
        end
      end

      def getlocal(index, level)
        if operands_unification
          # Specialize the getlocal instruction based on the level of the
          # local variable. If it's 0 or 1, then there's a specialized
          # instruction that will look at the current scope or the parent
          # scope, respectively, and requires fewer operands.
          case level
          when 0
            push(GetLocalWC0.new(index))
          when 1
            push(GetLocalWC1.new(index))
          else
            push(GetLocal.new(index, level))
          end
        else
          push(GetLocal.new(index, level))
        end
      end

      def getspecial(key, type)
        push(GetSpecial.new(key, type))
      end

      def intern
        push(Intern.new)
      end

      def invokeblock(calldata)
        push(InvokeBlock.new(calldata))
      end

      def invokesuper(calldata, block_iseq)
        push(InvokeSuper.new(calldata, block_iseq))
      end

      def jump(label)
        push(Jump.new(label))
      end

      def leave
        push(Leave.new)
      end

      def newarray(number)
        push(NewArray.new(number))
      end

      def newarraykwsplat(number)
        push(NewArrayKwSplat.new(number))
      end

      def newhash(number)
        push(NewHash.new(number))
      end

      def newrange(exclude_end)
        push(NewRange.new(exclude_end))
      end

      def nop
        push(Nop.new)
      end

      def objtostring(calldata)
        push(ObjToString.new(calldata))
      end

      def once(iseq, cache)
        push(Once.new(iseq, cache))
      end

      def opt_aref_with(object, calldata)
        push(OptArefWith.new(object, calldata))
      end

      def opt_aset_with(object, calldata)
        push(OptAsetWith.new(object, calldata))
      end

      def opt_getconstant_path(names)
        if RUBY_VERSION < "3.2" || !inline_const_cache
          cache = nil
          getinlinecache = nil

          if inline_const_cache
            cache = inline_storage
            getinlinecache = opt_getinlinecache(-1, cache)

            if names[0] == :""
              names.shift
              pop
              putobject(Object)
            end
          elsif names[0] == :""
            names.shift
            putobject(Object)
          else
            putnil
          end

          names.each_with_index do |name, index|
            putobject(index == 0)
            getconstant(name)
          end

          if inline_const_cache
            opt_setinlinecache(cache)
            getinlinecache.patch!(self)
          end
        else
          push(OptGetConstantPath.new(names))
        end
      end

      def opt_getinlinecache(label, cache)
        push(Legacy::OptGetInlineCache.new(label, cache))
      end

      def opt_newarray_max(length)
        if specialized_instruction
          push(OptNewArrayMax.new(length))
        else
          newarray(length)
          send(YARV.calldata(:max))
        end
      end

      def opt_newarray_min(length)
        if specialized_instruction
          push(OptNewArrayMin.new(length))
        else
          newarray(length)
          send(YARV.calldata(:min))
        end
      end

      def opt_setinlinecache(cache)
        push(Legacy::OptSetInlineCache.new(cache))
      end

      def opt_str_freeze(object)
        if specialized_instruction
          push(OptStrFreeze.new(object, YARV.calldata(:freeze)))
        else
          putstring(object)
          send(YARV.calldata(:freeze))
        end
      end

      def opt_str_uminus(object)
        if specialized_instruction
          push(OptStrUMinus.new(object, YARV.calldata(:-@)))
        else
          putstring(object)
          send(YARV.calldata(:-@))
        end
      end

      def pop
        push(Pop.new)
      end

      def putnil
        push(PutNil.new)
      end

      def putobject(object)
        if operands_unification
          # Specialize the putobject instruction based on the value of the
          # object. If it's 0 or 1, then there's a specialized instruction
          # that will push the object onto the stack and requires fewer
          # operands.
          if object.eql?(0)
            push(PutObjectInt2Fix0.new)
          elsif object.eql?(1)
            push(PutObjectInt2Fix1.new)
          else
            push(PutObject.new(object))
          end
        else
          push(PutObject.new(object))
        end
      end

      def putself
        push(PutSelf.new)
      end

      def putspecialobject(object)
        push(PutSpecialObject.new(object))
      end

      def putstring(object)
        push(PutString.new(object))
      end

      def send(calldata, block_iseq = nil)
        if specialized_instruction && !block_iseq &&
             !calldata.flag?(CallData::CALL_ARGS_BLOCKARG)
          # Specialize the send instruction. If it doesn't have a block
          # attached, then we will replace it with an opt_send_without_block
          # and do further specializations based on the called method and the
          # number of arguments.
          case [calldata.method, calldata.argc]
          when [:length, 0]
            push(OptLength.new(calldata))
          when [:size, 0]
            push(OptSize.new(calldata))
          when [:empty?, 0]
            push(OptEmptyP.new(calldata))
          when [:nil?, 0]
            push(OptNilP.new(calldata))
          when [:succ, 0]
            push(OptSucc.new(calldata))
          when [:!, 0]
            push(OptNot.new(calldata))
          when [:+, 1]
            push(OptPlus.new(calldata))
          when [:-, 1]
            push(OptMinus.new(calldata))
          when [:*, 1]
            push(OptMult.new(calldata))
          when [:/, 1]
            push(OptDiv.new(calldata))
          when [:%, 1]
            push(OptMod.new(calldata))
          when [:==, 1]
            push(OptEq.new(calldata))
          when [:!=, 1]
            push(OptNEq.new(YARV.calldata(:==, 1), calldata))
          when [:=~, 1]
            push(OptRegExpMatch2.new(calldata))
          when [:<, 1]
            push(OptLT.new(calldata))
          when [:<=, 1]
            push(OptLE.new(calldata))
          when [:>, 1]
            push(OptGT.new(calldata))
          when [:>=, 1]
            push(OptGE.new(calldata))
          when [:<<, 1]
            push(OptLTLT.new(calldata))
          when [:[], 1]
            push(OptAref.new(calldata))
          when [:&, 1]
            push(OptAnd.new(calldata))
          when [:|, 1]
            push(OptOr.new(calldata))
          when [:[]=, 2]
            push(OptAset.new(calldata))
          else
            push(OptSendWithoutBlock.new(calldata))
          end
        else
          push(Send.new(calldata, block_iseq))
        end
      end

      def setblockparam(index, level)
        push(SetBlockParam.new(index, level))
      end

      def setclassvariable(name)
        if RUBY_VERSION < "3.0"
          push(Legacy::SetClassVariable.new(name))
        else
          push(SetClassVariable.new(name, inline_storage_for(name)))
        end
      end

      def setconstant(name)
        push(SetConstant.new(name))
      end

      def setglobal(name)
        push(SetGlobal.new(name))
      end

      def setinstancevariable(name)
        if RUBY_VERSION < "3.2"
          push(SetInstanceVariable.new(name, inline_storage_for(name)))
        else
          push(SetInstanceVariable.new(name, inline_storage))
        end
      end

      def setlocal(index, level)
        if operands_unification
          # Specialize the setlocal instruction based on the level of the
          # local variable. If it's 0 or 1, then there's a specialized
          # instruction that will write to the current scope or the parent
          # scope, respectively, and requires fewer operands.
          case level
          when 0
            push(SetLocalWC0.new(index))
          when 1
            push(SetLocalWC1.new(index))
          else
            push(SetLocal.new(index, level))
          end
        else
          push(SetLocal.new(index, level))
        end
      end

      def setn(number)
        push(SetN.new(number))
      end

      def setspecial(key)
        push(SetSpecial.new(key))
      end

      def splatarray(flag)
        push(SplatArray.new(flag))
      end

      def swap
        push(Swap.new)
      end

      def topn(number)
        push(TopN.new(number))
      end

      def toregexp(options, length)
        push(ToRegExp.new(options, length))
      end
    end
  end
end
