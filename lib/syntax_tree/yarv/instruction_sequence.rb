# frozen_string_literal: true

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    # This class is meant to mirror RubyVM::InstructionSequence. It contains a
    # list of instructions along with the metadata pertaining to them. It also
    # functions as a builder for the instruction sequence.
    class InstructionSequence
      # This provides a handle to the rb_iseq_load function, which allows you
      # to pass a serialized iseq to Ruby and have it return a
      # RubyVM::InstructionSequence object.
      def self.iseq_load(iseq)
        require "fiddle"

        @iseq_load_function ||=
          Fiddle::Function.new(
            Fiddle::Handle::DEFAULT["rb_iseq_load"],
            [Fiddle::TYPE_VOIDP] * 3,
            Fiddle::TYPE_VOIDP
          )

        Fiddle.dlunwrap(@iseq_load_function.call(Fiddle.dlwrap(iseq), 0, nil))
      rescue LoadError
        raise "Could not load the Fiddle library"
      rescue NameError
        raise "Unable to find rb_iseq_load"
      rescue Fiddle::DLError
        raise "Unable to perform a dynamic load"
      end

      # When the list of instructions is first being created, it's stored as a
      # linked list. This is to make it easier to perform peephole optimizations
      # and other transformations like instruction specialization.
      class InstructionList
        class Node
          attr_accessor :value, :next_node

          def initialize(value, next_node = nil)
            @value = value
            @next_node = next_node
          end
        end

        include Enumerable
        attr_reader :head_node, :tail_node

        def initialize
          @head_node = nil
          @tail_node = nil
        end

        def each(&_blk)
          return to_enum(__method__) unless block_given?
          each_node { |node| yield node.value }
        end

        def each_node
          return to_enum(__method__) unless block_given?
          node = head_node

          while node
            yield node, node.value
            node = node.next_node
          end
        end

        def push(instruction)
          node = Node.new(instruction)

          if head_node.nil?
            @head_node = node
            @tail_node = node
          else
            @tail_node.next_node = node
            @tail_node = node
          end

          node
        end
      end

      MAGIC = "YARVInstructionSequence/SimpleDataFormat"

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

      # This represents the destination of instructions that jump. Initially it
      # does not track its position so that when we perform optimizations the
      # indices don't get messed up.
      class Label
        attr_reader :name

        # When we're serializing the instruction sequence, we need to be able to
        # look up the label from the branch instructions and then access the
        # subsequent node. So we'll store the reference here.
        attr_accessor :node

        def initialize(name = nil)
          @name = name
        end

        def patch!(name)
          @name = name
        end

        def inspect
          name.inspect
        end
      end

      # The name of the instruction sequence.
      attr_reader :name

      # The source location of the instruction sequence.
      attr_reader :file, :line

      # The type of the instruction sequence.
      attr_reader :type

      # The parent instruction sequence, if there is one.
      attr_reader :parent_iseq

      # This is the list of information about the arguments to this
      # instruction sequence.
      attr_accessor :argument_size
      attr_reader :argument_options

      # The catch table for this instruction sequence.
      attr_reader :catch_table

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
      attr_reader :options

      def initialize(
        name,
        file,
        line,
        type,
        parent_iseq = nil,
        options = Compiler::Options.new
      )
        @name = name
        @file = file
        @line = line
        @type = type
        @parent_iseq = parent_iseq

        @argument_size = 0
        @argument_options = {}
        @catch_table = []

        @local_table = LocalTable.new
        @inline_storages = {}
        @insns = InstructionList.new
        @storage_index = 0
        @stack = Stack.new

        @options = options
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
        insns
          .each
          .inject(0) do |sum, insn|
            case insn
            when Integer, Label, Symbol
              sum
            else
              sum + insn.length
            end
          end
      end

      def eval
        InstructionSequence.iseq_load(to_a).eval
      end

      def to_a
        versions = RUBY_VERSION.split(".").map(&:to_i)

        # Dump all of the instructions into a flat list.
        dumped =
          insns.map do |insn|
            case insn
            when Integer, Symbol
              insn
            when Label
              insn.name
            else
              insn.to_a(self)
            end
          end

        dumped_options = argument_options.dup
        dumped_options[:opt].map!(&:name) if dumped_options[:opt]

        metadata = {
          arg_size: argument_size,
          local_size: local_table.size,
          stack_max: stack.maximum_size,
          node_id: -1,
          node_ids: [-1] * insns.length
        }

        metadata[:parser] = :prism if RUBY_VERSION >= "3.3"

        # Next, return the instruction sequence as an array.
        [
          MAGIC,
          versions[0],
          versions[1],
          1,
          metadata,
          name,
          file,
          "<compiled>",
          line,
          type,
          local_table.names,
          dumped_options,
          catch_table.map(&:to_a),
          dumped
        ]
      end

      def to_cfg
        ControlFlowGraph.compile(self)
      end

      def to_dfg
        to_cfg.to_dfg
      end

      def to_son
        to_dfg.to_son
      end

      def disasm
        fmt = Disassembler.new
        fmt.enqueue(self)
        fmt.format!
        fmt.string
      end

      def inspect
        "#<ISeq:#{name}@<compiled>:1 (#{line},0)-(#{line},0)>"
      end

      # This method converts our linked list of instructions into a final array
      # and performs any other compilation steps necessary.
      def compile!
        specialize_instructions! if options.specialized_instruction?

        catch_table.each do |catch_entry|
          if !catch_entry.is_a?(CatchBreak) && catch_entry.iseq
            catch_entry.iseq.compile!
          end
        end

        length = 0
        insns.each do |insn|
          case insn
          when Integer, Symbol
            # skip
          when Label
            insn.patch!(:"label_#{length}")
          when DefineClass
            insn.class_iseq.compile!
            length += insn.length
          when DefineMethod, DefineSMethod
            insn.method_iseq.compile!
            length += insn.length
          when InvokeSuper, Send
            insn.block_iseq.compile! if insn.block_iseq
            length += insn.length
          when Once
            insn.iseq.compile!
            length += insn.length
          else
            length += insn.length
          end
        end

        @insns = insns.to_a
      end

      def specialize_instructions!
        insns.each_node do |node, value|
          case value
          when NewArray
            next unless node.next_node

            next_node = node.next_node
            next unless next_node.value.is_a?(Send)
            next if next_node.value.block_iseq

            calldata = next_node.value.calldata
            next unless calldata.flags == CallData::CALL_ARGS_SIMPLE
            next unless calldata.argc == 0

            case calldata.method
            when :min
              node.value =
                if RUBY_VERSION < "3.3"
                  Legacy::OptNewArrayMin.new(value.number)
                else
                  OptNewArraySend.new(value.number, :min)
                end

              node.next_node = next_node.next_node
            when :max
              node.value =
                if RUBY_VERSION < "3.3"
                  Legacy::OptNewArrayMax.new(value.number)
                else
                  OptNewArraySend.new(value.number, :max)
                end

              node.next_node = next_node.next_node
            when :hash
              next if RUBY_VERSION < "3.3"
              node.value = OptNewArraySend.new(value.number, :hash)
              node.next_node = next_node.next_node
            end
          when PutObject, PutString
            next unless node.next_node
            next if value.is_a?(PutObject) && !value.object.is_a?(String)

            next_node = node.next_node
            next unless next_node.value.is_a?(Send)
            next if next_node.value.block_iseq

            calldata = next_node.value.calldata
            next unless calldata.flags == CallData::CALL_ARGS_SIMPLE
            next unless calldata.argc == 0

            case calldata.method
            when :freeze
              node.value = OptStrFreeze.new(value.object, calldata)
              node.next_node = next_node.next_node
            when :-@
              node.value = OptStrUMinus.new(value.object, calldata)
              node.next_node = next_node.next_node
            end
          when Send
            calldata = value.calldata

            if !value.block_iseq &&
                 !calldata.flag?(CallData::CALL_ARGS_BLOCKARG)
              # Specialize the send instruction. If it doesn't have a block
              # attached, then we will replace it with an opt_send_without_block
              # and do further specializations based on the called method and
              # the number of arguments.
              node.value =
                case [calldata.method, calldata.argc]
                when [:length, 0]
                  OptLength.new(calldata)
                when [:size, 0]
                  OptSize.new(calldata)
                when [:empty?, 0]
                  OptEmptyP.new(calldata)
                when [:nil?, 0]
                  OptNilP.new(calldata)
                when [:succ, 0]
                  OptSucc.new(calldata)
                when [:!, 0]
                  OptNot.new(calldata)
                when [:+, 1]
                  OptPlus.new(calldata)
                when [:-, 1]
                  OptMinus.new(calldata)
                when [:*, 1]
                  OptMult.new(calldata)
                when [:/, 1]
                  OptDiv.new(calldata)
                when [:%, 1]
                  OptMod.new(calldata)
                when [:==, 1]
                  OptEq.new(calldata)
                when [:!=, 1]
                  OptNEq.new(YARV.calldata(:==, 1), calldata)
                when [:=~, 1]
                  OptRegExpMatch2.new(calldata)
                when [:<, 1]
                  OptLT.new(calldata)
                when [:<=, 1]
                  OptLE.new(calldata)
                when [:>, 1]
                  OptGT.new(calldata)
                when [:>=, 1]
                  OptGE.new(calldata)
                when [:<<, 1]
                  OptLTLT.new(calldata)
                when [:[], 1]
                  OptAref.new(calldata)
                when [:&, 1]
                  OptAnd.new(calldata)
                when [:|, 1]
                  OptOr.new(calldata)
                when [:[]=, 2]
                  OptAset.new(calldata)
                else
                  OptSendWithoutBlock.new(calldata)
                end
            end
          end
        end
      end

      ##########################################################################
      # Child instruction sequence methods
      ##########################################################################

      def child_iseq(name, line, type)
        InstructionSequence.new(name, file, line, type, self, options)
      end

      def block_child_iseq(line)
        current = self
        current = current.parent_iseq while current.type == :block
        child_iseq("block in #{current.name}", line, :block)
      end

      def class_child_iseq(name, line)
        child_iseq("<class:#{name}>", line, :class)
      end

      def method_child_iseq(name, line)
        child_iseq(name, line, :method)
      end

      def module_child_iseq(name, line)
        child_iseq("<module:#{name}>", line, :class)
      end

      def singleton_class_child_iseq(line)
        child_iseq("singleton class", line, :class)
      end

      ##########################################################################
      # Catch table methods
      ##########################################################################

      class CatchEntry
        attr_reader :iseq, :begin_label, :end_label, :exit_label, :restore_sp

        def initialize(iseq, begin_label, end_label, exit_label, restore_sp)
          @iseq = iseq
          @begin_label = begin_label
          @end_label = end_label
          @exit_label = exit_label
          @restore_sp = restore_sp
        end
      end

      class CatchBreak < CatchEntry
        def to_a
          [
            :break,
            iseq.to_a,
            begin_label.name,
            end_label.name,
            exit_label.name,
            restore_sp
          ]
        end
      end

      class CatchEnsure < CatchEntry
        def to_a
          [
            :ensure,
            iseq.to_a,
            begin_label.name,
            end_label.name,
            exit_label.name
          ]
        end
      end

      class CatchNext < CatchEntry
        def to_a
          [:next, nil, begin_label.name, end_label.name, exit_label.name]
        end
      end

      class CatchRedo < CatchEntry
        def to_a
          [:redo, nil, begin_label.name, end_label.name, exit_label.name]
        end
      end

      class CatchRescue < CatchEntry
        def to_a
          [
            :rescue,
            iseq.to_a,
            begin_label.name,
            end_label.name,
            exit_label.name
          ]
        end
      end

      class CatchRetry < CatchEntry
        def to_a
          [:retry, nil, begin_label.name, end_label.name, exit_label.name]
        end
      end

      def catch_break(iseq, begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchBreak.new(
          iseq,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      def catch_ensure(iseq, begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchEnsure.new(
          iseq,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      def catch_next(begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchNext.new(
          nil,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      def catch_redo(begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchRedo.new(
          nil,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      def catch_rescue(iseq, begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchRescue.new(
          iseq,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      def catch_retry(begin_label, end_label, exit_label, restore_sp)
        catch_table << CatchRetry.new(
          nil,
          begin_label,
          end_label,
          exit_label,
          restore_sp
        )
      end

      ##########################################################################
      # Instruction push methods
      ##########################################################################

      def label
        Label.new
      end

      def push(value)
        node = insns.push(value)

        case value
        when Array, Integer, Symbol
          value
        when Label
          value.node = node
          value
        else
          stack.change_by(-value.pops + value.pushes)
          value
        end
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

      def concattoarray(object)
        push(ConcatToArray.new(object))
      end

      def defineclass(name, class_iseq, flags)
        push(DefineClass.new(name, class_iseq, flags))
      end

      def defined(type, name, message)
        push(Defined.new(type, name, message))
      end

      def definedivar(name, cache, message)
        if RUBY_VERSION < "3.3"
          push(PutNil.new)
          push(Defined.new(Defined::TYPE_IVAR, name, message))
        else
          push(DefinedIVar.new(name, cache, message))
        end
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
        if options.operands_unification?
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

      def opt_case_dispatch(case_dispatch_hash, else_label)
        push(OptCaseDispatch.new(case_dispatch_hash, else_label))
      end

      def opt_getconstant_path(names)
        if RUBY_VERSION < "3.2" || !options.inline_const_cache?
          cache = nil
          cache_filled_label = nil

          if options.inline_const_cache?
            cache = inline_storage
            cache_filled_label = label
            opt_getinlinecache(cache_filled_label, cache)

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

          if options.inline_const_cache?
            opt_setinlinecache(cache)
            push(cache_filled_label)
          end
        else
          push(OptGetConstantPath.new(names))
        end
      end

      def opt_getinlinecache(label, cache)
        push(Legacy::OptGetInlineCache.new(label, cache))
      end

      def opt_setinlinecache(cache)
        push(Legacy::OptSetInlineCache.new(cache))
      end

      def pop
        push(Pop.new)
      end

      def pushtoarraykwsplat
        push(PushToArrayKwSplat.new)
      end

      def putchilledstring(object)
        push(PutChilledString.new(object))
      end

      def putnil
        push(PutNil.new)
      end

      def putobject(object)
        if options.operands_unification?
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
        push(Send.new(calldata, block_iseq))
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
        if options.operands_unification?
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

      def throw(type)
        push(Throw.new(type))
      end

      def topn(number)
        push(TopN.new(number))
      end

      def toregexp(options, length)
        push(ToRegExp.new(options, length))
      end

      # This method will create a new instruction sequence from a serialized
      # RubyVM::InstructionSequence object.
      def self.from(source, options = Compiler::Options.new, parent_iseq = nil)
        iseq =
          new(source[5], source[6], source[8], source[9], parent_iseq, options)

        # set up the labels object so that the labels are shared between the
        # location in the instruction sequence and the instructions that
        # reference them
        labels = Hash.new { |hash, name| hash[name] = Label.new(name) }

        # set up the correct argument size
        iseq.argument_size = source[4][:arg_size]

        # set up all of the locals
        source[10].each { |local| iseq.local_table.plain(local) }

        # set up the argument options
        iseq.argument_options.merge!(source[11])
        if iseq.argument_options[:opt]
          iseq.argument_options[:opt].map! { |opt| labels[opt] }
        end

        # track the child block iseqs so that our catch table can point to the
        # correctly created iseqs
        block_iseqs = []

        # set up all of the instructions
        source[13].each do |insn|
          # add line numbers
          if insn.is_a?(Integer)
            iseq.push(insn)
            next
          end

          # add events and labels
          if insn.is_a?(Symbol)
            if insn.start_with?("label_")
              iseq.push(labels[insn])
            else
              iseq.push(insn)
            end
            next
          end

          # add instructions, mapped to our own instruction classes
          type, *opnds = insn

          case type
          when :adjuststack
            iseq.adjuststack(opnds[0])
          when :anytostring
            iseq.anytostring
          when :branchif
            iseq.branchif(labels[opnds[0]])
          when :branchnil
            iseq.branchnil(labels[opnds[0]])
          when :branchunless
            iseq.branchunless(labels[opnds[0]])
          when :checkkeyword
            iseq.checkkeyword(iseq.local_table.size - opnds[0] + 2, opnds[1])
          when :checkmatch
            iseq.checkmatch(opnds[0])
          when :checktype
            iseq.checktype(opnds[0])
          when :concatarray
            iseq.concatarray
          when :concatstrings
            iseq.concatstrings(opnds[0])
          when :concattoarray
            iseq.concattoarray(opnds[0])
          when :defineclass
            iseq.defineclass(opnds[0], from(opnds[1], options, iseq), opnds[2])
          when :defined
            iseq.defined(opnds[0], opnds[1], opnds[2])
          when :definedivar
            iseq.definedivar(opnds[0], opnds[1], opnds[2])
          when :definemethod
            iseq.definemethod(opnds[0], from(opnds[1], options, iseq))
          when :definesmethod
            iseq.definesmethod(opnds[0], from(opnds[1], options, iseq))
          when :dup
            iseq.dup
          when :duparray
            iseq.duparray(opnds[0])
          when :duphash
            iseq.duphash(opnds[0])
          when :dupn
            iseq.dupn(opnds[0])
          when :expandarray
            iseq.expandarray(opnds[0], opnds[1])
          when :getblockparam, :getblockparamproxy, :getlocal, :getlocal_WC_0,
               :getlocal_WC_1, :setblockparam, :setlocal, :setlocal_WC_0,
               :setlocal_WC_1
            current = iseq
            level = 0

            case type
            when :getlocal_WC_1, :setlocal_WC_1
              level = 1
            when :getblockparam, :getblockparamproxy, :getlocal, :setblockparam,
                 :setlocal
              level = opnds[1]
            end

            level.times { current = current.parent_iseq }
            index = current.local_table.size - opnds[0] + 2

            case type
            when :getblockparam
              iseq.getblockparam(index, level)
            when :getblockparamproxy
              iseq.getblockparamproxy(index, level)
            when :getlocal, :getlocal_WC_0, :getlocal_WC_1
              iseq.getlocal(index, level)
            when :setblockparam
              iseq.setblockparam(index, level)
            when :setlocal, :setlocal_WC_0, :setlocal_WC_1
              iseq.setlocal(index, level)
            end
          when :getclassvariable
            iseq.push(GetClassVariable.new(opnds[0], opnds[1]))
          when :getconstant
            iseq.getconstant(opnds[0])
          when :getglobal
            iseq.getglobal(opnds[0])
          when :getinstancevariable
            iseq.push(GetInstanceVariable.new(opnds[0], opnds[1]))
          when :getspecial
            iseq.getspecial(opnds[0], opnds[1])
          when :intern
            iseq.intern
          when :invokeblock
            iseq.invokeblock(CallData.from(opnds[0]))
          when :invokesuper
            block_iseq = opnds[1] ? from(opnds[1], options, iseq) : nil
            iseq.invokesuper(CallData.from(opnds[0]), block_iseq)
          when :jump
            iseq.jump(labels[opnds[0]])
          when :leave
            iseq.leave
          when :newarray
            iseq.newarray(opnds[0])
          when :newarraykwsplat
            iseq.newarraykwsplat(opnds[0])
          when :newhash
            iseq.newhash(opnds[0])
          when :newrange
            iseq.newrange(opnds[0])
          when :nop
            iseq.nop
          when :objtostring
            iseq.objtostring(CallData.from(opnds[0]))
          when :once
            iseq.once(from(opnds[0], options, iseq), opnds[1])
          when :opt_and, :opt_aref, :opt_aset, :opt_div, :opt_empty_p, :opt_eq,
               :opt_ge, :opt_gt, :opt_le, :opt_length, :opt_lt, :opt_ltlt,
               :opt_minus, :opt_mod, :opt_mult, :opt_nil_p, :opt_not, :opt_or,
               :opt_plus, :opt_regexpmatch2, :opt_send_without_block, :opt_size,
               :opt_succ
            iseq.send(CallData.from(opnds[0]), nil)
          when :opt_aref_with
            iseq.opt_aref_with(opnds[0], CallData.from(opnds[1]))
          when :opt_aset_with
            iseq.opt_aset_with(opnds[0], CallData.from(opnds[1]))
          when :opt_case_dispatch
            hash =
              opnds[0]
                .each_slice(2)
                .to_h
                .transform_values { |value| labels[value] }
            iseq.opt_case_dispatch(hash, labels[opnds[1]])
          when :opt_getconstant_path
            iseq.opt_getconstant_path(opnds[0])
          when :opt_getinlinecache
            iseq.opt_getinlinecache(labels[opnds[0]], opnds[1])
          when :opt_newarray_max
            iseq.newarray(opnds[0])
            iseq.send(YARV.calldata(:max))
          when :opt_newarray_min
            iseq.newarray(opnds[0])
            iseq.send(YARV.calldata(:min))
          when :opt_newarray_send
            mid = opnds[1]
            if RUBY_VERSION >= "3.4"
              mid = %i[max min hash pack pack_buffer include?][mid - 1]
            end

            iseq.newarray(opnds[0])
            iseq.send(CallData.new(mid))
          when :opt_neq
            iseq.push(
              OptNEq.new(CallData.from(opnds[0]), CallData.from(opnds[1]))
            )
          when :opt_setinlinecache
            iseq.opt_setinlinecache(opnds[0])
          when :opt_str_freeze
            iseq.putstring(opnds[0])
            iseq.send(YARV.calldata(:freeze))
          when :opt_str_uminus
            iseq.putstring(opnds[0])
            iseq.send(YARV.calldata(:-@))
          when :pop
            iseq.pop
          when :pushtoarraykwsplat
            iseq.pushtoarraykwsplat
          when :putchilledstring
            iseq.putchilledstring(opnds[0])
          when :putnil
            iseq.putnil
          when :putobject
            iseq.putobject(opnds[0])
          when :putobject_INT2FIX_0_
            iseq.putobject(0)
          when :putobject_INT2FIX_1_
            iseq.putobject(1)
          when :putself
            iseq.putself
          when :putstring
            iseq.putstring(opnds[0])
          when :putspecialobject
            iseq.putspecialobject(opnds[0])
          when :send
            block_iseq = opnds[1] ? from(opnds[1], options, iseq) : nil
            block_iseqs << block_iseq if block_iseq
            iseq.send(CallData.from(opnds[0]), block_iseq)
          when :setclassvariable
            iseq.push(SetClassVariable.new(opnds[0], opnds[1]))
          when :setconstant
            iseq.setconstant(opnds[0])
          when :setglobal
            iseq.setglobal(opnds[0])
          when :setinstancevariable
            iseq.push(SetInstanceVariable.new(opnds[0], opnds[1]))
          when :setn
            iseq.setn(opnds[0])
          when :setspecial
            iseq.setspecial(opnds[0])
          when :splatarray
            iseq.splatarray(opnds[0])
          when :swap
            iseq.swap
          when :throw
            iseq.throw(opnds[0])
          when :topn
            iseq.topn(opnds[0])
          when :toregexp
            iseq.toregexp(opnds[0], opnds[1])
          else
            raise "Unknown instruction type: #{type}"
          end
        end

        # set up the catch table
        source[12].each do |entry|
          case entry[0]
          when :break
            if entry[1]
              break_iseq =
                block_iseqs.find do |block_iseq|
                  block_iseq.name == entry[1][5] &&
                    block_iseq.file == entry[1][6] &&
                    block_iseq.line == entry[1][8]
                end

              iseq.catch_break(
                break_iseq || from(entry[1], options, iseq),
                labels[entry[2]],
                labels[entry[3]],
                labels[entry[4]],
                entry[5]
              )
            else
              iseq.catch_break(
                nil,
                labels[entry[2]],
                labels[entry[3]],
                labels[entry[4]],
                entry[5]
              )
            end
          when :ensure
            iseq.catch_ensure(
              from(entry[1], options, iseq),
              labels[entry[2]],
              labels[entry[3]],
              labels[entry[4]],
              entry[5]
            )
          when :next
            iseq.catch_next(
              labels[entry[2]],
              labels[entry[3]],
              labels[entry[4]],
              entry[5]
            )
          when :rescue
            iseq.catch_rescue(
              from(entry[1], options, iseq),
              labels[entry[2]],
              labels[entry[3]],
              labels[entry[4]],
              entry[5]
            )
          when :redo
            iseq.catch_redo(
              labels[entry[2]],
              labels[entry[3]],
              labels[entry[4]],
              entry[5]
            )
          when :retry
            iseq.catch_retry(
              labels[entry[2]],
              labels[entry[3]],
              labels[entry[4]],
              entry[5]
            )
          else
            raise "unknown catch type: #{entry[0]}"
          end
        end

        iseq.compile! if iseq.type == :top
        iseq
      end
    end
  end
end
