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

      def initialize(type, name, parent_iseq, location)
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
      end

      def local_variable(name, level = 0)
        if (lookup = local_table.find(name, level))
          lookup
        elsif parent_iseq
          parent_iseq.local_variable(name, level + 1)
        end
      end

      def push(insn)
        insns << insn
        insn
      end

      def inline_storage
        storage = storage_index
        @storage_index += 1
        storage
      end

      def inline_storage_for(name)
        unless inline_storages.key?(name)
          inline_storages[name] = inline_storage
        end

        inline_storages[name]
      end

      def length
        insns.inject(0) do |sum, insn|
          insn.is_a?(Array) ? sum + insn.length : sum
        end
      end

      def each_child
        insns.each do |insn|
          insn[1..].each do |operand|
            yield operand if operand.is_a?(InstructionSequence)
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
          insns.map { |insn| serialize(insn) }
        ]
      end

      private

      def serialize(insn)
        case insn[0]
        when :checkkeyword, :getblockparam, :getblockparamproxy,
              :getlocal_WC_0, :getlocal_WC_1, :getlocal, :setlocal_WC_0,
              :setlocal_WC_1, :setlocal
          iseq = self

          case insn[0]
          when :getlocal_WC_1, :setlocal_WC_1
            iseq = iseq.parent_iseq
          when :getblockparam, :getblockparamproxy, :getlocal, :setlocal
            insn[2].times { iseq = iseq.parent_iseq }
          end

          # Here we need to map the local variable index to the offset
          # from the top of the stack where it will be stored.
          [insn[0], iseq.local_table.offset(insn[1]), *insn[2..]]
        when :defineclass
          [insn[0], insn[1], insn[2].to_a, insn[3]]
        when :definemethod, :definesmethod
          [insn[0], insn[1], insn[2].to_a]
        when :send
          # For any instructions that push instruction sequences onto the
          # stack, we need to call #to_a on them as well.
          [insn[0], insn[1], (insn[2].to_a if insn[2])]
        when :once
          [insn[0], insn[1].to_a, insn[2]]
        else
          insn
        end
      end
    end

    # This class is responsible for taking a compiled instruction sequence and
    # walking through it to generate equivalent Ruby code.
    class Disassembler
      attr_reader :iseq

      def initialize(iseq)
        @iseq = iseq
      end

      def to_ruby
        stack = []

        iseq.insns.each do |insn|
          case insn[0]
          when :leave
            stack << ReturnNode.new(arguments: Args.new(parts: [stack.pop], location: Location.default), location: Location.default)
          when :opt_mult
            left, right = stack.pop(2)
            stack << Binary.new(left: left, operator: :*, right: right, location: Location.default)
          when :opt_plus
            left, right = stack.pop(2)
            stack << Binary.new(left: left, operator: :+, right: right, location: Location.default)
          when :putobject
            case insn[1]
            when Float
              stack << FloatLiteral.new(value: insn[1].inspect, location: Location.default)
            when Integer
              stack << Int.new(value: insn[1].inspect, location: Location.default)
            when Rational
              stack << RationalLiteral.new(value: insn[1].inspect, location: Location.default)
            else
              raise "Unknown object type: #{insn[1].class.name}"
            end
          when :putobject_INT2FIX_1_
            stack << Int.new(value: "1", location: Location.default)
          else
            raise "Unknown instruction #{insn[0]}"
          end
        end

        Statements.new(nil, body: stack, location: Location.default)
      end
    end

    # This class serves as a layer of indirection between the instruction
    # sequence and the compiler. It allows us to provide different behavior
    # for certain instructions depending on the Ruby version. For example,
    # class variable reads and writes gained an inline cache in Ruby 3.0. So
    # we place the logic for checking the Ruby version in this class.
    class Builder
      attr_reader :iseq, :stack
      attr_reader :frozen_string_literal,
                  :operands_unification,
                  :specialized_instruction

      def initialize(
        iseq,
        frozen_string_literal: false,
        operands_unification: true,
        specialized_instruction: true
      )
        @iseq = iseq
        @stack = iseq.stack

        @frozen_string_literal = frozen_string_literal
        @operands_unification = operands_unification
        @specialized_instruction = specialized_instruction
      end

      # This creates a new label at the current length of the instruction
      # sequence. It is used as the operand for jump instructions.
      def label
        name = :"label_#{iseq.length}"
        iseq.insns.last == name ? name : event(name)
      end

      def event(name)
        iseq.push(name)
        name
      end

      def adjuststack(number)
        stack.change_by(-number)
        iseq.push([:adjuststack, number])
      end

      def anytostring
        stack.change_by(-2 + 1)
        iseq.push([:anytostring])
      end

      def branchif(index)
        stack.change_by(-1)
        iseq.push([:branchif, index])
      end

      def branchnil(index)
        stack.change_by(-1)
        iseq.push([:branchnil, index])
      end

      def branchunless(index)
        stack.change_by(-1)
        iseq.push([:branchunless, index])
      end

      def checkkeyword(index, keyword_index)
        stack.change_by(+1)
        iseq.push([:checkkeyword, index, keyword_index])
      end

      def concatarray
        stack.change_by(-2 + 1)
        iseq.push([:concatarray])
      end

      def concatstrings(number)
        stack.change_by(-number + 1)
        iseq.push([:concatstrings, number])
      end

      def defined(type, name, message)
        stack.change_by(-1 + 1)
        iseq.push([:defined, type, name, message])
      end

      def defineclass(name, class_iseq, flags)
        stack.change_by(-2 + 1)
        iseq.push([:defineclass, name, class_iseq, flags])
      end

      def definemethod(name, method_iseq)
        stack.change_by(0)
        iseq.push([:definemethod, name, method_iseq])
      end

      def definesmethod(name, method_iseq)
        stack.change_by(-1)
        iseq.push([:definesmethod, name, method_iseq])
      end

      def dup
        stack.change_by(-1 + 2)
        iseq.push([:dup])
      end

      def duparray(object)
        stack.change_by(+1)
        iseq.push([:duparray, object])
      end

      def duphash(object)
        stack.change_by(+1)
        iseq.push([:duphash, object])
      end

      def dupn(number)
        stack.change_by(+number)
        iseq.push([:dupn, number])
      end

      def expandarray(length, flag)
        stack.change_by(-1 + length)
        iseq.push([:expandarray, length, flag])
      end

      def getblockparam(index, level)
        stack.change_by(+1)
        iseq.push([:getblockparam, index, level])
      end

      def getblockparamproxy(index, level)
        stack.change_by(+1)
        iseq.push([:getblockparamproxy, index, level])
      end

      def getclassvariable(name)
        stack.change_by(+1)

        if RUBY_VERSION >= "3.0"
          iseq.push([:getclassvariable, name, iseq.inline_storage_for(name)])
        else
          iseq.push([:getclassvariable, name])
        end
      end

      def getconstant(name)
        stack.change_by(-2 + 1)
        iseq.push([:getconstant, name])
      end

      def getglobal(name)
        stack.change_by(+1)
        iseq.push([:getglobal, name])
      end

      def getinstancevariable(name)
        stack.change_by(+1)

        if RUBY_VERSION >= "3.2"
          iseq.push([:getinstancevariable, name, iseq.inline_storage])
        else
          inline_storage = iseq.inline_storage_for(name)
          iseq.push([:getinstancevariable, name, inline_storage])
        end
      end

      def getlocal(index, level)
        stack.change_by(+1)

        if operands_unification
          # Specialize the getlocal instruction based on the level of the
          # local variable. If it's 0 or 1, then there's a specialized
          # instruction that will look at the current scope or the parent
          # scope, respectively, and requires fewer operands.
          case level
          when 0
            iseq.push([:getlocal_WC_0, index])
          when 1
            iseq.push([:getlocal_WC_1, index])
          else
            iseq.push([:getlocal, index, level])
          end
        else
          iseq.push([:getlocal, index, level])
        end
      end

      def getspecial(key, type)
        stack.change_by(-0 + 1)
        iseq.push([:getspecial, key, type])
      end

      def intern
        stack.change_by(-1 + 1)
        iseq.push([:intern])
      end

      def invokeblock(method_id, argc, flag)
        stack.change_by(-argc + 1)
        iseq.push([:invokeblock, call_data(method_id, argc, flag)])
      end

      def invokesuper(method_id, argc, flag, block_iseq)
        stack.change_by(-(argc + 1) + 1)

        cdata = call_data(method_id, argc, flag)
        iseq.push([:invokesuper, cdata, block_iseq])
      end

      def jump(index)
        stack.change_by(0)
        iseq.push([:jump, index])
      end

      def leave
        stack.change_by(-1)
        iseq.push([:leave])
      end

      def newarray(length)
        stack.change_by(-length + 1)
        iseq.push([:newarray, length])
      end

      def newhash(length)
        stack.change_by(-length + 1)
        iseq.push([:newhash, length])
      end

      def newrange(flag)
        stack.change_by(-2 + 1)
        iseq.push([:newrange, flag])
      end

      def nop
        stack.change_by(0)
        iseq.push([:nop])
      end

      def objtostring(method_id, argc, flag)
        stack.change_by(-1 + 1)
        iseq.push([:objtostring, call_data(method_id, argc, flag)])
      end

      def once(postexe_iseq, inline_storage)
        stack.change_by(+1)
        iseq.push([:once, postexe_iseq, inline_storage])
      end

      def opt_getconstant_path(names)
        if RUBY_VERSION >= "3.2"
          stack.change_by(+1)
          iseq.push([:opt_getconstant_path, names])
        else
          inline_storage = iseq.inline_storage
          getinlinecache = opt_getinlinecache(-1, inline_storage)

          if names[0] == :""
            names.shift
            pop
            putobject(Object)
          end

          names.each_with_index do |name, index|
            putobject(index == 0)
            getconstant(name)
          end

          opt_setinlinecache(inline_storage)
          getinlinecache[1] = label
        end
      end

      def opt_getinlinecache(offset, inline_storage)
        stack.change_by(+1)
        iseq.push([:opt_getinlinecache, offset, inline_storage])
      end

      def opt_newarray_max(length)
        if specialized_instruction
          stack.change_by(-length + 1)
          iseq.push([:opt_newarray_max, length])
        else
          newarray(length)
          send(:max, 0, VM_CALL_ARGS_SIMPLE)
        end
      end

      def opt_newarray_min(length)
        if specialized_instruction
          stack.change_by(-length + 1)
          iseq.push([:opt_newarray_min, length])
        else
          newarray(length)
          send(:min, 0, VM_CALL_ARGS_SIMPLE)
        end
      end

      def opt_setinlinecache(inline_storage)
        stack.change_by(-1 + 1)
        iseq.push([:opt_setinlinecache, inline_storage])
      end

      def opt_str_freeze(value)
        if specialized_instruction
          stack.change_by(+1)
          iseq.push(
            [
              :opt_str_freeze,
              value,
              call_data(:freeze, 0, VM_CALL_ARGS_SIMPLE)
            ]
          )
        else
          putstring(value)
          send(:freeze, 0, VM_CALL_ARGS_SIMPLE)
        end
      end

      def opt_str_uminus(value)
        if specialized_instruction
          stack.change_by(+1)
          iseq.push(
            [:opt_str_uminus, value, call_data(:-@, 0, VM_CALL_ARGS_SIMPLE)]
          )
        else
          putstring(value)
          send(:-@, 0, VM_CALL_ARGS_SIMPLE)
        end
      end

      def pop
        stack.change_by(-1)
        iseq.push([:pop])
      end

      def putnil
        stack.change_by(+1)
        iseq.push([:putnil])
      end

      def putobject(object)
        stack.change_by(+1)

        if operands_unification
          # Specialize the putobject instruction based on the value of the
          # object. If it's 0 or 1, then there's a specialized instruction
          # that will push the object onto the stack and requires fewer
          # operands.
          if object.eql?(0)
            iseq.push([:putobject_INT2FIX_0_])
          elsif object.eql?(1)
            iseq.push([:putobject_INT2FIX_1_])
          else
            iseq.push([:putobject, object])
          end
        else
          iseq.push([:putobject, object])
        end
      end

      def putself
        stack.change_by(+1)
        iseq.push([:putself])
      end

      def putspecialobject(object)
        stack.change_by(+1)
        iseq.push([:putspecialobject, object])
      end

      def putstring(object)
        stack.change_by(+1)
        iseq.push([:putstring, object])
      end

      def send(method_id, argc, flag, block_iseq = nil)
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
            when [:length, 0] then iseq.push([:opt_length, cdata])
            when [:size, 0]   then iseq.push([:opt_size, cdata])
            when [:empty?, 0] then iseq.push([:opt_empty_p, cdata])
            when [:nil?, 0]   then iseq.push([:opt_nil_p, cdata])
            when [:succ, 0]   then iseq.push([:opt_succ, cdata])
            when [:!, 0]      then iseq.push([:opt_not, cdata])
            when [:+, 1]      then iseq.push([:opt_plus, cdata])
            when [:-, 1]      then iseq.push([:opt_minus, cdata])
            when [:*, 1]      then iseq.push([:opt_mult, cdata])
            when [:/, 1]      then iseq.push([:opt_div, cdata])
            when [:%, 1]      then iseq.push([:opt_mod, cdata])
            when [:==, 1]     then iseq.push([:opt_eq, cdata])
            when [:=~, 1]     then iseq.push([:opt_regexpmatch2, cdata])
            when [:<, 1]      then iseq.push([:opt_lt, cdata])
            when [:<=, 1]     then iseq.push([:opt_le, cdata])
            when [:>, 1]      then iseq.push([:opt_gt, cdata])
            when [:>=, 1]     then iseq.push([:opt_ge, cdata])
            when [:<<, 1]     then iseq.push([:opt_ltlt, cdata])
            when [:[], 1]     then iseq.push([:opt_aref, cdata])
            when [:&, 1]      then iseq.push([:opt_and, cdata])
            when [:|, 1]      then iseq.push([:opt_or, cdata])
            when [:[]=, 2]    then iseq.push([:opt_aset, cdata])
            when [:!=, 1]
              eql_data = call_data(:==, 1, VM_CALL_ARGS_SIMPLE)
              iseq.push([:opt_neq, eql_data, cdata])
            else
              iseq.push([:opt_send_without_block, cdata])
            end
          else
            iseq.push([:send, cdata, block_iseq])
          end
        else
          iseq.push([:send, cdata, block_iseq])
        end
      end

      def setclassvariable(name)
        stack.change_by(-1)

        if RUBY_VERSION >= "3.0"
          iseq.push([:setclassvariable, name, iseq.inline_storage_for(name)])
        else
          iseq.push([:setclassvariable, name])
        end
      end

      def setconstant(name)
        stack.change_by(-2)
        iseq.push([:setconstant, name])
      end

      def setglobal(name)
        stack.change_by(-1)
        iseq.push([:setglobal, name])
      end

      def setinstancevariable(name)
        stack.change_by(-1)

        if RUBY_VERSION >= "3.2"
          iseq.push([:setinstancevariable, name, iseq.inline_storage])
        else
          inline_storage = iseq.inline_storage_for(name)
          iseq.push([:setinstancevariable, name, inline_storage])
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
            iseq.push([:setlocal_WC_0, index])
          when 1
            iseq.push([:setlocal_WC_1, index])
          else
            iseq.push([:setlocal, index, level])
          end
        else
          iseq.push([:setlocal, index, level])
        end
      end

      def setn(number)
        stack.change_by(-1 + 1)
        iseq.push([:setn, number])
      end

      def splatarray(flag)
        stack.change_by(-1 + 1)
        iseq.push([:splatarray, flag])
      end

      def swap
        stack.change_by(-2 + 2)
        iseq.push([:swap])
      end

      def topn(number)
        stack.change_by(+1)
        iseq.push([:topn, number])
      end

      def toregexp(options, length)
        stack.change_by(-length + 1)
        iseq.push([:toregexp, options, length])
      end

      private

      # This creates a call data object that is used as the operand for the
      # send, invokesuper, and objtostring instructions.
      def call_data(method_id, argc, flag)
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

    # These constants correspond to the value passed as part of the defined
    # instruction. It's an enum defined in the CRuby codebase that tells that
    # instruction what kind of defined check to perform.
    DEFINED_NIL = 1
    DEFINED_IVAR = 2
    DEFINED_LVAR = 3
    DEFINED_GVAR = 4
    DEFINED_CVAR = 5
    DEFINED_CONST = 6
    DEFINED_METHOD = 7
    DEFINED_YIELD = 8
    DEFINED_ZSUPER = 9
    DEFINED_SELF = 10
    DEFINED_TRUE = 11
    DEFINED_FALSE = 12
    DEFINED_ASGN = 13
    DEFINED_EXPR = 14
    DEFINED_REF = 15
    DEFINED_FUNC = 16
    DEFINED_CONST_FROM = 17

    # These constants correspond to the value passed in the flags as part of
    # the defineclass instruction.
    VM_DEFINECLASS_TYPE_CLASS = 0
    VM_DEFINECLASS_TYPE_SINGLETON_CLASS = 1
    VM_DEFINECLASS_TYPE_MODULE = 2
    VM_DEFINECLASS_FLAG_SCOPED = 8
    VM_DEFINECLASS_FLAG_HAS_SUPERCLASS = 16
  end
end
