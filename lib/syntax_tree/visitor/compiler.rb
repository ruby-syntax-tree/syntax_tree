# frozen_string_literal: true

module SyntaxTree
  class Visitor
    # This class is an experiment in transforming Syntax Tree nodes into their
    # corresponding YARV instruction sequences. It attempts to mirror the
    # behavior of RubyVM::InstructionSequence.compile.
    #
    # You use this as with any other visitor. First you parse code into a tree,
    # then you visit it with this compiler. Visiting the root node of the tree
    # will return a SyntaxTree::Visitor::Compiler::InstructionSequence object.
    # With that object you can call #to_a on it, which will return a serialized
    # form of the instruction sequence as an array. This array _should_ mirror
    # the array given by RubyVM::InstructionSequence#to_a.
    #
    # As an example, here is how you would compile a single expression:
    #
    #     program = SyntaxTree.parse("1 + 2")
    #     program.accept(SyntaxTree::Visitor::Compiler.new).to_a
    #
    #     [
    #       "YARVInstructionSequence/SimpleDataFormat",
    #       3,
    #       1,
    #       1,
    #       {:arg_size=>0, :local_size=>0, :stack_max=>2},
    #       "<compiled>",
    #       "<compiled>",
    #       "<compiled>",
    #       1,
    #       :top,
    #       [],
    #       {},
    #       [],
    #       [
    #         [:putobject_INT2FIX_1_],
    #         [:putobject, 2],
    #         [:opt_plus, {:mid=>:+, :flag=>16, :orig_argc=>1}],
    #         [:leave]
    #       ]
    #     ]
    #
    # Note that this is the same output as calling:
    #
    #     RubyVM::InstructionSequence.compile("1 + 2").to_a
    #
    class Compiler < BasicVisitor
      # This visitor is responsible for converting Syntax Tree nodes into their
      # corresponding Ruby structures. This is used to convert the operands of
      # some instructions like putobject that push a Ruby object directly onto
      # the stack. It is only used when the entire structure can be represented
      # at compile-time, as opposed to constructed at run-time.
      class RubyVisitor < BasicVisitor
        # This error is raised whenever a node cannot be converted into a Ruby
        # object at compile-time.
        class CompilationError < StandardError
        end

        def visit_array(node)
          visit_all(node.contents.parts)
        end

        def visit_bare_assoc_hash(node)
          node.assocs.to_h do |assoc|
            # We can only convert regular key-value pairs. A double splat **
            # operator means it has to be converted at run-time.
            raise CompilationError unless assoc.is_a?(Assoc)
            [visit(assoc.key), visit(assoc.value)]
          end
        end

        def visit_float(node)
          node.value.to_f
        end

        alias visit_hash visit_bare_assoc_hash

        def visit_imaginary(node)
          node.value.to_c
        end

        def visit_int(node)
          node.value.to_i
        end

        def visit_label(node)
          node.value.chomp(":").to_sym
        end

        def visit_qsymbols(node)
          node.elements.map { |element| visit(element).to_sym }
        end

        def visit_qwords(node)
          visit_all(node.elements)
        end

        def visit_range(node)
          left, right = [visit(node.left), visit(node.right)]
          node.operator.value === ".." ? left..right : left...right
        end

        def visit_rational(node)
          node.value.to_r
        end

        def visit_regexp_literal(node)
          if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
            Regexp.new(node.parts.first.value, visit_regexp_literal_flags(node))
          else
            # Any interpolation of expressions or variables will result in the
            # regular expression being constructed at run-time.
            raise CompilationError
          end
        end

        # This isn't actually a visit method, though maybe it should be. It is
        # responsible for converting the set of string options on a regular
        # expression into its equivalent integer.
        def visit_regexp_literal_flags(node)
          node
            .options
            .chars
            .inject(0) do |accum, option|
              accum |
                case option
                when "i"
                  Regexp::IGNORECASE
                when "x"
                  Regexp::EXTENDED
                when "m"
                  Regexp::MULTILINE
                else
                  raise "Unknown regexp option: #{option}"
                end
            end
        end

        def visit_symbol_literal(node)
          node.value.value.to_sym
        end

        def visit_symbols(node)
          node.elements.map { |element| visit(element).to_sym }
        end

        def visit_tstring_content(node)
          node.value
        end

        def visit_word(node)
          if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
            node.parts.first.value
          else
            # Any interpolation of expressions or variables will result in the
            # string being constructed at run-time.
            raise CompilationError
          end
        end

        def visit_words(node)
          visit_all(node.elements)
        end

        def visit_unsupported(_node)
          raise CompilationError
        end

        # Please forgive the metaprogramming here. This is used to create visit
        # methods for every node that we did not explicitly handle. By default
        # each of these methods will raise a CompilationError.
        handled = instance_methods(false)
        (Visitor.instance_methods(false) - handled).each do |method|
          alias_method method, :visit_unsupported
        end
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

      # This represents every local variable associated with an instruction
      # sequence. There are two kinds of locals: plain locals that are what you
      # expect, and block proxy locals, which represent local variables
      # associated with blocks that were passed into the current instruction
      # sequence.
      class LocalTable
        # A local representing a block passed into the current instruction
        # sequence.
        class BlockProxyLocal
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

        # Add a BlockProxyLocal to the local table.
        def block_proxy(name)
          locals << BlockProxyLocal.new(name) unless has?(name)
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
          else
            raise "Unknown local variable: #{name}"
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
          insns.sum(&:length)
        end

        def each_child
          insns.each do |insn|
            insn[1..].each do |operand|
              yield operand if operand.is_a?(InstructionSequence)
            end
          end
        end

        def to_a
          versions = RUBY_VERSION.split(".").map(&:to_i)

          [
            "YARVInstructionSequence/SimpleDataFormat",
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
            1,
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
          when :checkkeyword, :getblockparamproxy, :getlocal_WC_0,
               :getlocal_WC_1, :getlocal, :setlocal_WC_0, :setlocal_WC_1,
               :setlocal
            iseq = self

            case insn[0]
            when :getlocal_WC_1, :setlocal_WC_1
              iseq = iseq.parent_iseq
            when :getblockparamproxy, :getlocal, :setlocal
              insn[2].times { iseq = iseq.parent_iseq }
            end

            # Here we need to map the local variable index to the offset
            # from the top of the stack where it will be stored.
            [insn[0], iseq.local_table.offset(insn[1]), *insn[2..]]
          when :defineclass
            [insn[0], insn[1], insn[2].to_a, insn[3]]
          when :definemethod
            [insn[0], insn[1], insn[2].to_a]
          when :send
            # For any instructions that push instruction sequences onto the
            # stack, we need to call #to_a on them as well.
            [insn[0], insn[1], (insn[2].to_a if insn[2])]
          else
            insn
          end
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
          :"label_#{iseq.length}"
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

        def branchunless(index)
          stack.change_by(-1)
          iseq.push([:branchunless, index])
        end

        def checkkeyword(index, keyword_index)
          stack.change_by(+1)
          iseq.push([:checkkeyword, index, keyword_index])
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

        def opt_setinlinecache(inline_storage)
          stack.change_by(-1 + 1)
          iseq.push([:opt_setinlinecache, inline_storage])
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

      # These options mirror the compilation options that we currently support
      # that can be also passed to RubyVM::InstructionSequence.compile.
      attr_reader :frozen_string_literal,
                  :operands_unification,
                  :specialized_instruction

      # The current instruction sequence that is being compiled.
      attr_reader :current_iseq

      # This is the current builder that is being used to construct the current
      # instruction sequence.
      attr_reader :builder

      # A boolean to track if we're currently compiling the last statement
      # within a set of statements. This information is necessary to determine
      # if we need to return the value of the last statement.
      attr_reader :last_statement

      def initialize(
        frozen_string_literal: false,
        operands_unification: true,
        specialized_instruction: true
      )
        @frozen_string_literal = frozen_string_literal
        @operands_unification = operands_unification
        @specialized_instruction = specialized_instruction

        @current_iseq = nil
        @builder = nil
        @last_statement = false
      end

      def visit_CHAR(node)
        if frozen_string_literal
          builder.putobject(node.value[1..])
        else
          builder.putstring(node.value[1..])
        end
      end

      def visit_alias(node)
        builder.putspecialobject(VM_SPECIAL_OBJECT_VMCORE)
        builder.putspecialobject(VM_SPECIAL_OBJECT_CBASE)
        visit(node.left)
        visit(node.right)
        builder.send(:"core#set_method_alias", 3, VM_CALL_ARGS_SIMPLE)
      end

      def visit_aref(node)
        visit(node.collection)
        visit(node.index)
        builder.send(:[], 1, VM_CALL_ARGS_SIMPLE)
      end

      def visit_arg_block(node)
        visit(node.value)
      end

      def visit_arg_paren(node)
        visit(node.arguments)
      end

      def visit_arg_star(node)
        visit(node.value)
        builder.splatarray(false)
      end

      def visit_args(node)
        visit_all(node.parts)
      end

      def visit_array(node)
        builder.duparray(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        visit_all(node.contents.parts)
        builder.newarray(node.contents.parts.length)
      end

      def visit_assign(node)
        case node.target
        when ARefField
          builder.putnil
          visit(node.target.collection)
          visit(node.target.index)
          visit(node.value)
          builder.setn(3)
          builder.send(:[]=, 2, VM_CALL_ARGS_SIMPLE)
          builder.pop
        when ConstPathField
          names = constant_names(node.target)
          name = names.pop

          if RUBY_VERSION >= "3.2"
            builder.opt_getconstant_path(names)
            visit(node.value)
            builder.swap
            builder.topn(1)
            builder.swap
            builder.setconstant(name)
          else
            visit(node.value)
            builder.dup if last_statement?
            builder.opt_getconstant_path(names)
            builder.setconstant(name)
          end
        when Field
          builder.putnil
          visit(node.target)
          visit(node.value)
          builder.setn(2)
          builder.send(:"#{node.target.name.value}=", 1, VM_CALL_ARGS_SIMPLE)
          builder.pop
        when TopConstField
          name = node.target.constant.value.to_sym

          if RUBY_VERSION >= "3.2"
            builder.putobject(Object)
            visit(node.value)
            builder.swap
            builder.topn(1)
            builder.swap
            builder.setconstant(name)
          else
            visit(node.value)
            builder.dup if last_statement?
            builder.putobject(Object)
            builder.setconstant(name)
          end
        when VarField
          visit(node.value)
          builder.dup if last_statement?

          case node.target.value
          when Const
            builder.putspecialobject(VM_SPECIAL_OBJECT_CONST_BASE)
            builder.setconstant(node.target.value.value.to_sym)
          when CVar
            builder.setclassvariable(node.target.value.value.to_sym)
          when GVar
            builder.setglobal(node.target.value.value.to_sym)
          when Ident
            local_variable = visit(node.target)
            builder.setlocal(local_variable.index, local_variable.level)
          when IVar
            builder.setinstancevariable(node.target.value.value.to_sym)
          end
        end
      end

      def visit_assoc(node)
        visit(node.key)
        visit(node.value)
      end

      def visit_assoc_splat(node)
        visit(node.value)
      end

      def visit_backref(node)
        builder.getspecial(1, 2 * node.value[1..].to_i)
      end

      def visit_bare_assoc_hash(node)
        builder.duphash(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        visit_all(node.assocs)
      end

      def visit_binary(node)
        case node.operator
        when :"&&"
          visit(node.left)
          builder.dup

          branchunless = builder.branchunless(-1)
          builder.pop

          visit(node.right)
          branchunless[1] = builder.label
        when :"||"
          visit(node.left)
          builder.dup

          branchif = builder.branchif(-1)
          builder.pop

          visit(node.right)
          branchif[1] = builder.label
        else
          visit(node.left)
          visit(node.right)
          builder.send(node.operator, 1, VM_CALL_ARGS_SIMPLE)
        end
      end

      def visit_blockarg(node)
        current_iseq.argument_options[:block_start] = current_iseq.argument_size
        current_iseq.local_table.block_proxy(node.name.value.to_sym)
        current_iseq.argument_size += 1
      end

      def visit_bodystmt(node)
        visit(node.statements)
      end

      def visit_call(node)
        node.receiver ? visit(node.receiver) : builder.putself

        visit(node.arguments)
        arg_parts = argument_parts(node.arguments)

        if arg_parts.last.is_a?(ArgBlock)
          flag = node.receiver.nil? ? VM_CALL_FCALL : 0
          flag |= VM_CALL_ARGS_BLOCKARG

          if arg_parts.any? { |part| part.is_a?(ArgStar) }
            flag |= VM_CALL_ARGS_SPLAT
          end

          if arg_parts.any? { |part| part.is_a?(BareAssocHash) }
            flag |= VM_CALL_KW_SPLAT
          end

          builder.send(node.message.value.to_sym, arg_parts.length - 1, flag)
        else
          flag = 0
          arg_parts.each do |arg_part|
            case arg_part
            when ArgStar
              flag |= VM_CALL_ARGS_SPLAT
            when BareAssocHash
              flag |= VM_CALL_KW_SPLAT
            end
          end

          flag |= VM_CALL_ARGS_SIMPLE if flag == 0
          flag |= VM_CALL_FCALL if node.receiver.nil?
          builder.send(node.message.value.to_sym, arg_parts.length, flag)
        end
      end

      def visit_command(node)
        call_node =
          CallNode.new(
            receiver: nil,
            operator: nil,
            message: node.message,
            arguments: node.arguments,
            location: node.location
          )

        call_node.comments.concat(node.comments)
        visit_call(call_node)
      end

      def visit_command_call(node)
        call_node =
          CallNode.new(
            receiver: node.receiver,
            operator: node.operator,
            message: node.message,
            arguments: node.arguments,
            location: node.location
          )

        call_node.comments.concat(node.comments)
        visit_call(call_node)
      end

      def visit_const_path_field(node)
        visit(node.parent)
      end

      def visit_const_path_ref(node)
        names = constant_names(node)
        builder.opt_getconstant_path(names)
      end

      def visit_def(node)
        method_iseq =
          with_instruction_sequence(
            :method,
            node.name.value,
            current_iseq,
            node
          ) do
            visit(node.params) if node.params
            visit(node.bodystmt)
            builder.leave
          end

        name = node.name.value.to_sym
        builder.definemethod(name, method_iseq)
        builder.putobject(name)
      end

      def visit_defined(node)
        case node.value
        when Assign
          # If we're assigning to a local variable, then we need to make sure
          # that we put it into the local table.
          if node.value.target.is_a?(VarField) &&
               node.value.target.value.is_a?(Ident)
            current_iseq.local_table.plain(node.value.target.value.value.to_sym)
          end

          builder.putobject("assignment")
        when VarRef
          value = node.value.value
          name = value.value.to_sym

          case value
          when Const
            builder.putnil
            builder.defined(DEFINED_CONST, name, "constant")
          when CVar
            builder.putnil
            builder.defined(DEFINED_CVAR, name, "class variable")
          when GVar
            builder.putnil
            builder.defined(DEFINED_GVAR, name, "global-variable")
          when Ident
            builder.putobject("local-variable")
          when IVar
            builder.putnil
            builder.defined(DEFINED_IVAR, name, "instance-variable")
          when Kw
            case name
            when :false
              builder.putobject("false")
            when :nil
              builder.putobject("nil")
            when :self
              builder.putobject("self")
            when :true
              builder.putobject("true")
            end
          end
        when VCall
          builder.putself

          name = node.value.value.value.to_sym
          builder.defined(DEFINED_FUNC, name, "method")
        when YieldNode
          builder.putnil
          builder.defined(DEFINED_YIELD, false, "yield")
        when ZSuper
          builder.putnil
          builder.defined(DEFINED_ZSUPER, false, "super")
        else
          builder.putobject("expression")
        end
      end

      def visit_dyna_symbol(node)
        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          builder.putobject(node.parts.first.value.to_sym)
        end
      end

      def visit_else(node)
        visit(node.statements)
        builder.pop unless last_statement?
      end

      def visit_field(node)
        visit(node.parent)
      end

      def visit_float(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_for(node)
        visit(node.collection)

        name = node.index.value.value.to_sym
        current_iseq.local_table.plain(name)

        block_iseq =
          with_instruction_sequence(
            :block,
            "block in #{current_iseq.name}",
            current_iseq,
            node.statements
          ) do
            current_iseq.argument_options[:lead_num] ||= 0
            current_iseq.argument_options[:lead_num] += 1
            current_iseq.argument_options[:ambiguous_param0] = true

            current_iseq.argument_size += 1
            current_iseq.local_table.plain(2)

            builder.getlocal(0, 0)

            local_variable = current_iseq.local_variable(name)
            builder.setlocal(local_variable.index, local_variable.level)
            builder.nop

            visit(node.statements)
            builder.leave
          end

        builder.send(:each, 0, 0, block_iseq)
      end

      def visit_hash(node)
        builder.duphash(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        visit_all(node.assocs)
        builder.newhash(node.assocs.length * 2)
      end

      def visit_heredoc(node)
        if node.beginning.value.end_with?("`")
          visit_xstring_literal(node)
        elsif node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          visit(node.parts.first)
        else
          visit_string_parts(node)
          builder.concatstrings(node.parts.length)
        end
      end

      def visit_if(node)
        visit(node.predicate)
        branchunless = builder.branchunless(-1)
        visit(node.statements)

        if last_statement?
          builder.leave
          branchunless[1] = builder.label

          node.consequent ? visit(node.consequent) : builder.putnil
        else
          builder.pop

          if node.consequent
            jump = builder.jump(-1)
            branchunless[1] = builder.label
            visit(node.consequent)
            jump[1] = builder.label
          else
            branchunless[1] = builder.label
          end
        end
      end

      def visit_imaginary(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_int(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_kwrest_param(node)
        current_iseq.argument_options[:kwrest] = current_iseq.argument_size
        current_iseq.argument_size += 1
        current_iseq.local_table.plain(node.name.value.to_sym)
      end

      def visit_label(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_module(node)
        name = node.constant.constant.value.to_sym
        module_iseq =
          with_instruction_sequence(
            :class,
            "<module:#{name}>",
            current_iseq,
            node
          ) do
            visit(node.bodystmt)
            builder.leave
          end

        flags = VM_DEFINECLASS_TYPE_MODULE

        case node.constant
        when ConstPathRef
          flags |= VM_DEFINECLASS_FLAG_SCOPED
          visit(node.constant.parent)
        when ConstRef
          builder.putspecialobject(VM_SPECIAL_OBJECT_CONST_BASE)
        when TopConstRef
          flags |= VM_DEFINECLASS_FLAG_SCOPED
          builder.putobject(Object)
        end

        builder.putnil
        builder.defineclass(name, module_iseq, flags)
      end

      def visit_not(node)
        visit(node.statement)
        builder.send(:!, 0, VM_CALL_ARGS_SIMPLE)
      end

      def visit_opassign(node)
        flag = VM_CALL_ARGS_SIMPLE
        if node.target.is_a?(ConstPathField) || node.target.is_a?(TopConstField)
          flag |= VM_CALL_FCALL
        end

        case (operator = node.operator.value.chomp("=").to_sym)
        when :"&&"
          branchunless = nil

          with_opassign(node) do
            builder.dup
            branchunless = builder.branchunless(-1)
            builder.pop
            visit(node.value)
          end

          case node.target
          when ARefField
            builder.leave
            branchunless[1] = builder.label
            builder.setn(3)
            builder.adjuststack(3)
          when ConstPathField, TopConstField
            branchunless[1] = builder.label
            builder.swap
            builder.pop
          else
            branchunless[1] = builder.label
          end
        when :"||"
          if node.target.is_a?(ConstPathField) ||
               node.target.is_a?(TopConstField)
            opassign_defined(node)
            builder.swap
            builder.pop
          elsif node.target.is_a?(VarField) &&
                [Const, CVar, GVar].include?(node.target.value.class)
            opassign_defined(node)
          else
            branchif = nil

            with_opassign(node) do
              builder.dup
              branchif = builder.branchif(-1)
              builder.pop
              visit(node.value)
            end

            if node.target.is_a?(ARefField)
              builder.leave
              branchif[1] = builder.label
              builder.setn(3)
              builder.adjuststack(3)
            else
              branchif[1] = builder.label
            end
          end
        else
          with_opassign(node) do
            visit(node.value)
            builder.send(operator, 1, flag)
          end
        end
      end

      def visit_params(node)
        argument_options = current_iseq.argument_options

        if node.requireds.any?
          argument_options[:lead_num] = 0

          node.requireds.each do |required|
            current_iseq.local_table.plain(required.value.to_sym)
            current_iseq.argument_size += 1
            argument_options[:lead_num] += 1
          end
        end

        node.optionals.each do |(optional, value)|
          index = current_iseq.local_table.size
          name = optional.value.to_sym

          current_iseq.local_table.plain(name)
          current_iseq.argument_size += 1

          unless argument_options.key?(:opt)
            argument_options[:opt] = [builder.label]
          end

          visit(value)
          builder.setlocal(index, 0)
          current_iseq.argument_options[:opt] << builder.label
        end

        visit(node.rest) if node.rest

        if node.posts.any?
          argument_options[:post_start] = current_iseq.argument_size
          argument_options[:post_num] = 0

          node.posts.each do |post|
            current_iseq.local_table.plain(post.value.to_sym)
            current_iseq.argument_size += 1
            argument_options[:post_num] += 1
          end
        end

        if node.keywords.any?
          argument_options[:kwbits] = 0
          argument_options[:keyword] = []
          checkkeywords = []

          node.keywords.each_with_index do |(keyword, value), keyword_index|
            name = keyword.value.chomp(":").to_sym
            index = current_iseq.local_table.size

            current_iseq.local_table.plain(name)
            current_iseq.argument_size += 1
            argument_options[:kwbits] += 1

            if value.nil?
              argument_options[:keyword] << name
            else
              begin
                compiled = value.accept(RubyVisitor.new)
                argument_options[:keyword] << [name, compiled]
              rescue RubyVisitor::CompilationError
                argument_options[:keyword] << [name]
                checkkeywords << builder.checkkeyword(-1, keyword_index)
                branchif = builder.branchif(-1)
                visit(value)
                builder.setlocal(index, 0)
                branchif[1] = builder.label
              end
            end
          end

          name = node.keyword_rest ? 3 : 2
          current_iseq.argument_size += 1
          current_iseq.local_table.plain(name)

          lookup = current_iseq.local_table.find(name, 0)
          checkkeywords.each { |checkkeyword| checkkeyword[1] = lookup.index }
        end

        visit(node.keyword_rest) if node.keyword_rest
        visit(node.block) if node.block
      end

      def visit_paren(node)
        visit(node.contents)
      end

      def visit_program(node)
        node.statements.body.each do |statement|
          break unless statement.is_a?(Comment)

          if statement.value == "# frozen_string_literal: true"
            @frozen_string_literal = true
          end
        end

        statements =
          node.statements.body.select do |statement|
            case statement
            when Comment, EmbDoc, EndContent, VoidStmt
              false
            else
              true
            end
          end

        with_instruction_sequence(:top, "<compiled>", nil, node) do
          if statements.empty?
            builder.putnil
          else
            *statements, last_statement = statements
            visit_all(statements)
            with_last_statement { visit(last_statement) }
          end

          builder.leave
        end
      end

      def visit_qsymbols(node)
        builder.duparray(node.accept(RubyVisitor.new))
      end

      def visit_qwords(node)
        if frozen_string_literal
          builder.duparray(node.accept(RubyVisitor.new))
        else
          visit_all(node.elements)
          builder.newarray(node.elements.length)
        end
      end

      def visit_range(node)
        builder.putobject(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        visit(node.left)
        visit(node.right)
        builder.newrange(node.operator.value == ".." ? 0 : 1)
      end

      def visit_rational(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_regexp_literal(node)
        builder.putobject(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        visit_string_parts(node)

        flags = RubyVisitor.new.visit_regexp_literal_flags(node)
        builder.toregexp(flags, node.parts.length)
      end

      def visit_rest_param(node)
        current_iseq.local_table.plain(node.name.value.to_sym)
        current_iseq.argument_options[:rest_start] = current_iseq.argument_size
        current_iseq.argument_size += 1
      end

      def visit_statements(node)
        statements =
          node.body.select do |statement|
            case statement
            when Comment, EmbDoc, EndContent, VoidStmt
              false
            else
              true
            end
          end

        statements.empty? ? builder.putnil : visit_all(statements)
      end

      def visit_string_concat(node)
        value = node.left.parts.first.value + node.right.parts.first.value
        content = TStringContent.new(value: value, location: node.location)

        literal =
          StringLiteral.new(
            parts: [content],
            quote: node.left.quote,
            location: node.location
          )
        visit_string_literal(literal)
      end

      def visit_string_embexpr(node)
        visit(node.statements)
      end

      def visit_string_literal(node)
        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          visit(node.parts.first)
        else
          visit_string_parts(node)
          builder.concatstrings(node.parts.length)
        end
      end

      def visit_super(node)
        builder.putself
        visit(node.arguments)
        builder.invokesuper(
          nil,
          argument_parts(node.arguments).length,
          VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE | VM_CALL_SUPER,
          nil
        )
      end

      def visit_symbol_literal(node)
        builder.putobject(node.accept(RubyVisitor.new))
      end

      def visit_symbols(node)
        builder.duparray(node.accept(RubyVisitor.new))
      rescue RubyVisitor::CompilationError
        node.elements.each do |element|
          if element.parts.length == 1 &&
               element.parts.first.is_a?(TStringContent)
            builder.putobject(element.parts.first.value.to_sym)
          else
            length = element.parts.length
            unless element.parts.first.is_a?(TStringContent)
              builder.putobject("")
              length += 1
            end

            visit_string_parts(element)
            builder.concatstrings(length)
            builder.intern
          end
        end

        builder.newarray(node.elements.length)
      end

      def visit_top_const_ref(node)
        builder.opt_getconstant_path(constant_names(node))
      end

      def visit_tstring_content(node)
        if frozen_string_literal
          builder.putobject(node.accept(RubyVisitor.new))
        else
          builder.putstring(node.accept(RubyVisitor.new))
        end
      end

      def visit_unary(node)
        visit(node.statement)

        method_id =
          case node.operator
          when "+", "-"
            :"#{node.operator}@"
          else
            node.operator.to_sym
          end

        builder.send(method_id, 0, VM_CALL_ARGS_SIMPLE)
      end

      def visit_undef(node)
        node.symbols.each_with_index do |symbol, index|
          builder.pop if index != 0
          builder.putspecialobject(VM_SPECIAL_OBJECT_VMCORE)
          builder.putspecialobject(VM_SPECIAL_OBJECT_CBASE)
          visit(symbol)
          builder.send(:"core#undef_method", 2, VM_CALL_ARGS_SIMPLE)
        end
      end

      def visit_var_field(node)
        case node.value
        when CVar, IVar
          name = node.value.value.to_sym
          current_iseq.inline_storage_for(name)
        when Ident
          name = node.value.value.to_sym
          current_iseq.local_table.plain(name)
          current_iseq.local_variable(name)
        end
      end

      def visit_var_ref(node)
        case node.value
        when Const
          builder.opt_getconstant_path(constant_names(node))
        when CVar
          name = node.value.value.to_sym
          builder.getclassvariable(name)
        when GVar
          builder.getglobal(node.value.value.to_sym)
        when Ident
          lookup = current_iseq.local_variable(node.value.value.to_sym)

          case lookup.local
          when LocalTable::BlockProxyLocal
            builder.getblockparamproxy(lookup.index, lookup.level)
          when LocalTable::PlainLocal
            builder.getlocal(lookup.index, lookup.level)
          end
        when IVar
          name = node.value.value.to_sym
          builder.getinstancevariable(name)
        when Kw
          case node.value.value
          when "false"
            builder.putobject(false)
          when "nil"
            builder.putnil
          when "self"
            builder.putself
          when "true"
            builder.putobject(true)
          end
        end
      end

      def visit_vcall(node)
        builder.putself

        flag = VM_CALL_FCALL | VM_CALL_VCALL | VM_CALL_ARGS_SIMPLE
        builder.send(node.value.value.to_sym, 0, flag)
      end

      def visit_while(node)
        jumps = []

        jumps << builder.jump(-1)
        builder.putnil
        builder.pop
        jumps << builder.jump(-1)

        label = builder.label
        visit(node.statements)
        builder.pop
        jumps.each { |jump| jump[1] = builder.label }

        visit(node.predicate)
        builder.branchif(label)
        builder.putnil if last_statement?
      end

      def visit_word(node)
        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          visit(node.parts.first)
        else
          length = node.parts.length
          unless node.parts.first.is_a?(TStringContent)
            builder.putobject("")
            length += 1
          end

          visit_string_parts(node)
          builder.concatstrings(length)
        end
      end

      def visit_words(node)
        converted = nil

        if frozen_string_literal
          begin
            converted = node.accept(RubyVisitor.new)
          rescue RubyVisitor::CompilationError
          end
        end

        if converted
          builder.duparray(converted)
        else
          visit_all(node.elements)
          builder.newarray(node.elements.length)
        end
      end

      def visit_xstring_literal(node)
        builder.putself
        visit_string_parts(node)
        builder.concatstrings(node.parts.length) if node.parts.length > 1
        builder.send(:`, 1, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE)
      end

      def visit_yield(node)
        builder.invokeblock(nil, 0, VM_CALL_ARGS_SIMPLE)
      end

      def visit_zsuper(_node)
        builder.putself
        builder.invokesuper(
          nil,
          0,
          VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE | VM_CALL_SUPER | VM_CALL_ZSUPER,
          nil
        )
      end

      private

      # This is a helper that is used in places where arguments may be present
      # or they may be wrapped in parentheses. It's meant to descend down the
      # tree and return an array of argument nodes.
      def argument_parts(node)
        case node
        when nil
          []
        when Args
          node.parts
        when ArgParen
          node.arguments.parts
        end
      end

      # Constant names when they are being assigned or referenced come in as a
      # tree, but it's more convenient to work with them as an array. This
      # method converts them into that array. This is nice because it's the
      # operand that goes to opt_getconstant_path in Ruby 3.2.
      def constant_names(node)
        current = node
        names = []

        while current.is_a?(ConstPathField) || current.is_a?(ConstPathRef)
          names.unshift(current.constant.value.to_sym)
          current = current.parent
        end

        case current
        when VarField, VarRef
          names.unshift(current.value.value.to_sym)
        when TopConstRef
          names.unshift(current.constant.value.to_sym)
          names.unshift(:"")
        end

        names
      end

      # For the most part when an OpAssign (operator assignment) node with a ||=
      # operator is being compiled it's a matter of reading the target, checking
      # if the value should be evaluated, evaluating it if so, and then writing
      # the result back to the target.
      #
      # However, in certain kinds of assignments (X, ::X, X::Y, @@x, and $x) we
      # first check if the value is defined using the defined instruction. I
      # don't know why it is necessary, and suspect that it isn't.
      def opassign_defined(node)
        case node.target
        when ConstPathField
          visit(node.target.parent)
          name = node.target.constant.value.to_sym

          builder.dup
          builder.defined(DEFINED_CONST_FROM, name, true)
        when TopConstField
          name = node.target.constant.value.to_sym

          builder.putobject(Object)
          builder.dup
          builder.defined(DEFINED_CONST_FROM, name, true)
        when VarField
          name = node.target.value.value.to_sym
          builder.putnil

          case node.target.value
          when Const
            builder.defined(DEFINED_CONST, name, true)
          when CVar
            builder.defined(DEFINED_CVAR, name, true)
          when GVar
            builder.defined(DEFINED_GVAR, name, true)
          end
        end

        branchunless = builder.branchunless(-1)

        case node.target
        when ConstPathField, TopConstField
          builder.dup
          builder.putobject(true)
          builder.getconstant(name)
        when VarField
          case node.target.value
          when Const
            builder.opt_getconstant_path(constant_names(node.target))
          when CVar
            builder.getclassvariable(name)
          when GVar
            builder.getglobal(name)
          end
        end

        builder.dup
        branchif = builder.branchif(-1)
        builder.pop

        branchunless[1] = builder.label
        visit(node.value)

        case node.target
        when ConstPathField, TopConstField
          builder.dupn(2)
          builder.swap
          builder.setconstant(name)
        when VarField
          builder.dup

          case node.target.value
          when Const
            builder.putspecialobject(VM_SPECIAL_OBJECT_CONST_BASE)
            builder.setconstant(name)
          when CVar
            builder.setclassvariable(name)
          when GVar
            builder.setglobal(name)
          end
        end

        branchif[1] = builder.label
      end

      # Whenever a value is interpolated into a string-like structure, these
      # three instructions are pushed.
      def push_interpolate
        builder.dup
        builder.objtostring(:to_s, 0, VM_CALL_FCALL | VM_CALL_ARGS_SIMPLE)
        builder.anytostring
      end

      # There are a lot of nodes in the AST that act as contains of parts of
      # strings. This includes things like string literals, regular expressions,
      # heredocs, etc. This method will visit all the parts of a string within
      # those containers.
      def visit_string_parts(node)
        node.parts.each do |part|
          case part
          when StringDVar
            visit(part.variable)
            push_interpolate
          when StringEmbExpr
            visit(part)
            push_interpolate
          when TStringContent
            builder.putobject(part.accept(RubyVisitor.new))
          end
        end
      end

      # The current instruction sequence that we're compiling is always stored
      # on the compiler. When we descend into a node that has its own
      # instruction sequence, this method can be called to temporarily set the
      # new value of the instruction sequence, yield, and then set it back.
      def with_instruction_sequence(type, name, parent_iseq, node)
        previous_iseq = current_iseq
        previous_builder = builder

        begin
          iseq = InstructionSequence.new(type, name, parent_iseq, node.location)

          @current_iseq = iseq
          @builder =
            Builder.new(
              iseq,
              frozen_string_literal: frozen_string_literal,
              operands_unification: operands_unification,
              specialized_instruction: specialized_instruction
            )

          yield
          iseq
        ensure
          @current_iseq = previous_iseq
          @builder = previous_builder
        end
      end

      # When we're compiling the last statement of a set of statements within a
      # scope, the instructions sometimes change from pops to leaves. These
      # kinds of peephole optimizations can reduce the overall number of
      # instructions. Therefore, we keep track of whether we're compiling the
      # last statement of a scope and allow visit methods to query that
      # information.
      def with_last_statement
        @last_statement = true

        begin
          yield
        ensure
          @last_statement = false
        end
      end

      def last_statement?
        @last_statement
      end

      # OpAssign nodes can have a number of different kinds of nodes as their
      # "target" (i.e., the left-hand side of the assignment). When compiling
      # these nodes we typically need to first fetch the current value of the
      # variable, then perform some kind of action, then store the result back
      # into the variable. This method handles that by first fetching the value,
      # then yielding to the block, then storing the result.
      def with_opassign(node)
        case node.target
        when ARefField
          builder.putnil
          visit(node.target.collection)
          visit(node.target.index)

          builder.dupn(2)
          builder.send(:[], 1, VM_CALL_ARGS_SIMPLE)

          yield

          builder.setn(3)
          builder.send(:[]=, 2, VM_CALL_ARGS_SIMPLE)
          builder.pop
        when ConstPathField
          name = node.target.constant.value.to_sym

          visit(node.target.parent)
          builder.dup
          builder.putobject(true)
          builder.getconstant(name)

          yield

          if node.operator.value == "&&="
            builder.dupn(2)
          else
            builder.swap
            builder.topn(1)
          end

          builder.swap
          builder.setconstant(name)
        when TopConstField
          name = node.target.constant.value.to_sym

          builder.putobject(Object)
          builder.dup
          builder.putobject(true)
          builder.getconstant(name)

          yield

          if node.operator.value == "&&="
            builder.dupn(2)
          else
            builder.swap
            builder.topn(1)
          end

          builder.swap
          builder.setconstant(name)
        when VarField
          case node.target.value
          when Const
            names = constant_names(node.target)
            builder.opt_getconstant_path(names)

            yield

            builder.dup
            builder.putspecialobject(VM_SPECIAL_OBJECT_CONST_BASE)
            builder.setconstant(names.last)
          when CVar
            name = node.target.value.value.to_sym
            builder.getclassvariable(name)

            yield

            builder.dup
            builder.setclassvariable(name)
          when GVar
            name = node.target.value.value.to_sym
            builder.getglobal(name)

            yield

            builder.dup
            builder.setglobal(name)
          when Ident
            local_variable = visit(node.target)
            builder.getlocal(local_variable.index, local_variable.level)

            yield

            builder.dup
            builder.setlocal(local_variable.index, local_variable.level)
          when IVar
            name = node.target.value.value.to_sym
            builder.getinstancevariable(name)

            yield

            builder.dup
            builder.setinstancevariable(name)
          end
        end
      end
    end
  end
end
