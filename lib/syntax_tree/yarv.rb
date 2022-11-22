# frozen_string_literal: true

module SyntaxTree
  module YARV
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

    # This represents every local variable associated with an instruction
    # sequence. There are two kinds of locals: plain locals that are what you
    # expect, and block proxy locals, which represent local variables
    # associated with blocks that were passed into the current instruction
    # sequence.
    class LocalTable
      # A local representing a block passed into the current instruction
      # sequence.
      class BlockLocal
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      # A regular local variable.
      class PlainLocal
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      # The result of looking up a local variable in the current local table.
      class Lookup
        attr_reader :local, :index, :level

        def initialize(local, index, level)
          @local = local
          @index = index
          @level = level
        end
      end

      attr_reader :locals

      def initialize
        @locals = []
      end

      def find(name, level)
        index = locals.index { |local| local.name == name }
        Lookup.new(locals[index], index, level) if index
      end

      def has?(name)
        locals.any? { |local| local.name == name }
      end

      def names
        locals.map(&:name)
      end

      def size
        locals.length
      end

      # Add a BlockLocal to the local table.
      def block(name)
        locals << BlockLocal.new(name) unless has?(name)
      end

      # Add a PlainLocal to the local table.
      def plain(name)
        locals << PlainLocal.new(name) unless has?(name)
      end

      # This is the offset from the top of the stack where this local variable
      # lives.
      def offset(index)
        size - (index - 3) - 1
      end
    end

    # This class is meant to mirror RubyVM::InstructionSequence. It contains a
    # list of instructions along with the metadata pertaining to them. It also
    # functions as a builder for the instruction sequence.
    class InstructionSequence
      MAGIC = "YARVInstructionSequence/SimpleDataFormat"

      # This provides a handle to the rb_iseq_load function, which allows you to
      # pass a serialized iseq to Ruby and have it return a
      # RubyVM::InstructionSequence object.
      ISEQ_LOAD =
        Fiddle::Function.new(
          Fiddle::Handle::DEFAULT["rb_iseq_load"],
          [Fiddle::TYPE_VOIDP] * 3,
          Fiddle::TYPE_VOIDP
        )

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
                  :operands_unification,
                  :specialized_instruction

      def initialize(
        type,
        name,
        parent_iseq,
        location,
        frozen_string_literal: false,
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
            case insn
            when Integer, Symbol
              insn
            when Array
              case insn[0]
              when :setlocal_WC_0, :setlocal_WC_1, :setlocal
                iseq = self

                case insn[0]
                when :setlocal_WC_1
                  iseq = iseq.parent_iseq
                when :setlocal
                  insn[2].times { iseq = iseq.parent_iseq }
                end

                # Here we need to map the local variable index to the offset
                # from the top of the stack where it will be stored.
                [insn[0], iseq.local_table.offset(insn[1]), *insn[2..]]
              when :send
                # For any instructions that push instruction sequences onto the
                # stack, we need to call #to_a on them as well.
                [insn[0], insn[1], (insn[2].to_a if insn[2])]
              when :once
                [insn[0], insn[1].to_a, insn[2]]
              else
                insn
              end
            else
              insn.to_a(self)
            end
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
          push(GetClassVariableUncached.new(name))
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
        stack.change_by(-0 + 1)
        push([:getspecial, key, type])
      end

      def intern
        stack.change_by(-1 + 1)
        push([:intern])
      end

      def invokeblock(method_id, argc, flag = VM_CALL_ARGS_SIMPLE)
        stack.change_by(-argc + 1)
        push([:invokeblock, call_data(method_id, argc, flag)])
      end

      def invokesuper(method_id, argc, flag, block_iseq)
        stack.change_by(-(argc + 1) + 1)

        cdata = call_data(method_id, argc, flag)
        push([:invokesuper, cdata, block_iseq])
      end

      def jump(index)
        stack.change_by(0)
        push([:jump, index])
      end

      def leave
        stack.change_by(-1)
        push([:leave])
      end

      def newarray(length)
        stack.change_by(-length + 1)
        push([:newarray, length])
      end

      def newhash(length)
        stack.change_by(-length + 1)
        push([:newhash, length])
      end

      def newrange(flag)
        stack.change_by(-2 + 1)
        push([:newrange, flag])
      end

      def nop
        stack.change_by(0)
        push([:nop])
      end

      def objtostring(method_id, argc, flag)
        stack.change_by(-1 + 1)
        push([:objtostring, call_data(method_id, argc, flag)])
      end

      def once(postexe_iseq, inline_storage)
        stack.change_by(+1)
        push([:once, postexe_iseq, inline_storage])
      end

      def opt_aref_with(object, method_id, argc, flag = VM_CALL_ARGS_SIMPLE)
        stack.change_by(-1 + 1)
        push([:opt_aref_with, object, call_data(method_id, argc, flag)])
      end

      def opt_getconstant_path(names)
        if RUBY_VERSION >= "3.2"
          stack.change_by(+1)
          push([:opt_getconstant_path, names])
        else
          const_inline_storage = inline_storage
          getinlinecache = opt_getinlinecache(-1, const_inline_storage)

          if names[0] == :""
            names.shift
            pop
            putobject(Object)
          end

          names.each_with_index do |name, index|
            putobject(index == 0)
            getconstant(name)
          end

          opt_setinlinecache(const_inline_storage)
          getinlinecache[1] = label
        end
      end

      def opt_getinlinecache(offset, inline_storage)
        stack.change_by(+1)
        push([:opt_getinlinecache, offset, inline_storage])
      end

      def opt_newarray_max(length)
        if specialized_instruction
          stack.change_by(-length + 1)
          push([:opt_newarray_max, length])
        else
          newarray(length)
          send(:max, 0)
        end
      end

      def opt_newarray_min(length)
        if specialized_instruction
          stack.change_by(-length + 1)
          push([:opt_newarray_min, length])
        else
          newarray(length)
          send(:min, 0)
        end
      end

      def opt_setinlinecache(inline_storage)
        stack.change_by(-1 + 1)
        push([:opt_setinlinecache, inline_storage])
      end

      def opt_str_freeze(value)
        if specialized_instruction
          stack.change_by(+1)
          push([:opt_str_freeze, value, call_data(:freeze, 0)])
        else
          putstring(value)
          send(:freeze, 0)
        end
      end

      def opt_str_uminus(value)
        if specialized_instruction
          stack.change_by(+1)
          push([:opt_str_uminus, value, call_data(:-@, 0)])
        else
          putstring(value)
          send(:-@, 0)
        end
      end

      def pop
        stack.change_by(-1)
        push([:pop])
      end

      def putnil
        stack.change_by(+1)
        push([:putnil])
      end

      def putobject(object)
        stack.change_by(+1)

        if operands_unification
          # Specialize the putobject instruction based on the value of the
          # object. If it's 0 or 1, then there's a specialized instruction
          # that will push the object onto the stack and requires fewer
          # operands.
          if object.eql?(0)
            push([:putobject_INT2FIX_0_])
          elsif object.eql?(1)
            push([:putobject_INT2FIX_1_])
          else
            push([:putobject, object])
          end
        else
          push([:putobject, object])
        end
      end

      def putself
        stack.change_by(+1)
        push([:putself])
      end

      def putspecialobject(object)
        stack.change_by(+1)
        push([:putspecialobject, object])
      end

      def putstring(object)
        stack.change_by(+1)
        push([:putstring, object])
      end

      def send(method_id, argc, flag = VM_CALL_ARGS_SIMPLE, block_iseq = nil)
        stack.change_by(-(argc + 1) + 1)
        cdata = call_data(method_id, argc, flag)

        if specialized_instruction
          # Specialize the send instruction. If it doesn't have a block
          # attached, then we will replace it with an opt_send_without_block
          # and do further specializations based on the called method and the
          # number of arguments.

          # stree-ignore
          if !block_iseq && (flag & VM_CALL_ARGS_BLOCKARG) == 0
            case [method_id, argc]
            when [:length, 0] then push([:opt_length, cdata])
            when [:size, 0]   then push([:opt_size, cdata])
            when [:empty?, 0] then push([:opt_empty_p, cdata])
            when [:nil?, 0]   then push([:opt_nil_p, cdata])
            when [:succ, 0]   then push([:opt_succ, cdata])
            when [:!, 0]      then push([:opt_not, cdata])
            when [:+, 1]      then push([:opt_plus, cdata])
            when [:-, 1]      then push([:opt_minus, cdata])
            when [:*, 1]      then push([:opt_mult, cdata])
            when [:/, 1]      then push([:opt_div, cdata])
            when [:%, 1]      then push([:opt_mod, cdata])
            when [:==, 1]     then push([:opt_eq, cdata])
            when [:=~, 1]     then push([:opt_regexpmatch2, cdata])
            when [:<, 1]      then push([:opt_lt, cdata])
            when [:<=, 1]     then push([:opt_le, cdata])
            when [:>, 1]      then push([:opt_gt, cdata])
            when [:>=, 1]     then push([:opt_ge, cdata])
            when [:<<, 1]     then push([:opt_ltlt, cdata])
            when [:[], 1]     then push([:opt_aref, cdata])
            when [:&, 1]      then push([:opt_and, cdata])
            when [:|, 1]      then push([:opt_or, cdata])
            when [:[]=, 2]    then push([:opt_aset, cdata])
            when [:!=, 1]
              push([:opt_neq, call_data(:==, 1), cdata])
            else
              push([:opt_send_without_block, cdata])
            end
          else
            push([:send, cdata, block_iseq])
          end
        else
          push([:send, cdata, block_iseq])
        end
      end

      def setclassvariable(name)
        stack.change_by(-1)

        if RUBY_VERSION >= "3.0"
          push([:setclassvariable, name, inline_storage_for(name)])
        else
          push([:setclassvariable, name])
        end
      end

      def setconstant(name)
        stack.change_by(-2)
        push([:setconstant, name])
      end

      def setglobal(name)
        stack.change_by(-1)
        push([:setglobal, name])
      end

      def setinstancevariable(name)
        stack.change_by(-1)

        if RUBY_VERSION >= "3.2"
          push([:setinstancevariable, name, inline_storage])
        else
          push([:setinstancevariable, name, inline_storage_for(name)])
        end
      end

      def setlocal(index, level)
        stack.change_by(-1)

        if operands_unification
          # Specialize the setlocal instruction based on the level of the
          # local variable. If it's 0 or 1, then there's a specialized
          # instruction that will write to the current scope or the parent
          # scope, respectively, and requires fewer operands.
          case level
          when 0
            push([:setlocal_WC_0, index])
          when 1
            push([:setlocal_WC_1, index])
          else
            push([:setlocal, index, level])
          end
        else
          push([:setlocal, index, level])
        end
      end

      def setn(number)
        stack.change_by(-1 + 1)
        push([:setn, number])
      end

      def splatarray(flag)
        stack.change_by(-1 + 1)
        push([:splatarray, flag])
      end

      def swap
        stack.change_by(-2 + 2)
        push([:swap])
      end

      def topn(number)
        stack.change_by(+1)
        push([:topn, number])
      end

      def toregexp(options, length)
        stack.change_by(-length + 1)
        push([:toregexp, options, length])
      end

      private

      # This creates a call data object that is used as the operand for the
      # send, invokesuper, and objtostring instructions.
      def call_data(method_id, argc, flag = VM_CALL_ARGS_SIMPLE)
        { mid: method_id, flag: flag, orig_argc: argc }
      end
    end

    # These constants correspond to the putspecialobject instruction. They are
    # used to represent special objects that are pushed onto the stack.
    VM_SPECIAL_OBJECT_VMCORE = 1
    VM_SPECIAL_OBJECT_CBASE = 2
    VM_SPECIAL_OBJECT_CONST_BASE = 3

    # These constants correspond to the flag passed as part of the call data
    # structure on the send instruction. They are used to represent various
    # metadata about the callsite (e.g., were keyword arguments used?, was a
    # block given?, etc.).
    VM_CALL_ARGS_SPLAT = 1 << 0
    VM_CALL_ARGS_BLOCKARG = 1 << 1
    VM_CALL_FCALL = 1 << 2
    VM_CALL_VCALL = 1 << 3
    VM_CALL_ARGS_SIMPLE = 1 << 4
    VM_CALL_BLOCKISEQ = 1 << 5
    VM_CALL_KWARG = 1 << 6
    VM_CALL_KW_SPLAT = 1 << 7
    VM_CALL_TAILCALL = 1 << 8
    VM_CALL_SUPER = 1 << 9
    VM_CALL_ZSUPER = 1 << 10
    VM_CALL_OPT_SEND = 1 << 11
    VM_CALL_KW_SPLAT_MUT = 1 << 12
  end
end
