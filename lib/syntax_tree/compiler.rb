# frozen_string_literal: true

module SyntaxTree
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

      # This will attempt to compile the given node. If it's possible, then
      # it will return the compiled object. Otherwise it will return nil.
      def self.compile(node)
        node.accept(new)
      rescue CompilationError
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

      def visit_mrhs(node)
        visit_all(node.parts)
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

      def visit_var_ref(node)
        raise CompilationError unless node.value.is_a?(Kw)

        case node.value.value
        when "nil"
          nil
        when "true"
          true
        when "false"
          false
        else
          raise CompilationError
        end
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

    # These options mirror the compilation options that we currently support
    # that can be also passed to RubyVM::InstructionSequence.compile.
    attr_reader :frozen_string_literal,
                :operands_unification,
                :specialized_instruction

    # The current instruction sequence that is being compiled.
    attr_reader :iseq

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

      @iseq = nil
      @last_statement = false
    end

    def visit_BEGIN(node)
      visit(node.statements)
    end

    def visit_CHAR(node)
      if frozen_string_literal
        iseq.putobject(node.value[1..])
      else
        iseq.putstring(node.value[1..])
      end
    end

    def visit_END(node)
      once_iseq =
        with_child_iseq(iseq.block_child_iseq(node.location)) do
          postexe_iseq =
            with_child_iseq(iseq.block_child_iseq(node.location)) do
              iseq.event(:RUBY_EVENT_B_CALL)

              *statements, last_statement = node.statements.body
              visit_all(statements)
              with_last_statement { visit(last_statement) }

              iseq.event(:RUBY_EVENT_B_RETURN)
              iseq.leave
            end

          iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
          iseq.send(:"core#set_postexe", 0, YARV::VM_CALL_FCALL, postexe_iseq)
          iseq.leave
        end

      iseq.once(once_iseq, iseq.inline_storage)
      iseq.pop
    end

    def visit_alias(node)
      iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
      iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CBASE)
      visit(node.left)
      visit(node.right)
      iseq.send(:"core#set_method_alias", 3)
    end

    def visit_aref(node)
      visit(node.collection)

      if !frozen_string_literal && specialized_instruction && (node.index.parts.length == 1)
        arg = node.index.parts.first

        if arg.is_a?(StringLiteral) && (arg.parts.length == 1)
          string_part = arg.parts.first

          if string_part.is_a?(TStringContent)
            iseq.opt_aref_with(string_part.value, :[], 1)
            return
          end
        end
      end

      visit(node.index)
      iseq.send(:[], 1)
    end

    def visit_arg_block(node)
      visit(node.value)
    end

    def visit_arg_paren(node)
      visit(node.arguments)
    end

    def visit_arg_star(node)
      visit(node.value)
      iseq.splatarray(false)
    end

    def visit_args(node)
      visit_all(node.parts)
    end

    def visit_array(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.duparray(compiled)
      elsif node.contents && node.contents.parts.length == 1 &&
            node.contents.parts.first.is_a?(BareAssocHash) &&
            node.contents.parts.first.assocs.length == 1 &&
            node.contents.parts.first.assocs.first.is_a?(AssocSplat)
        iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
        iseq.newhash(0)
        visit(node.contents.parts.first)
        iseq.send(:"core#hash_merge_kwd", 2)
        iseq.newarraykwsplat(1)
      else
        length = 0

        node.contents.parts.each do |part|
          if part.is_a?(ArgStar)
            if length > 0
              iseq.newarray(length)
              length = 0
            end

            visit(part.value)
            iseq.concatarray
          else
            visit(part)
            length += 1
          end
        end

        iseq.newarray(length) if length > 0
        iseq.concatarray if length > 0 && length != node.contents.parts.length
      end
    end

    def visit_assign(node)
      case node.target
      when ARefField
        if !frozen_string_literal && specialized_instruction && (node.target.index.parts.length == 1)
          arg = node.target.index.parts.first
  
          if arg.is_a?(StringLiteral) && (arg.parts.length == 1)
            string_part = arg.parts.first
  
            if string_part.is_a?(TStringContent)
              visit(node.target.collection)
              visit(node.value)
              iseq.swap
              iseq.topn(1)
              iseq.opt_aset_with(string_part.value, :[]=, 2)
              iseq.pop
              return
            end
          end
        end

        iseq.putnil
        visit(node.target.collection)
        visit(node.target.index)
        visit(node.value)
        iseq.setn(3)
        iseq.send(:[]=, 2)
        iseq.pop
      when ConstPathField
        names = constant_names(node.target)
        name = names.pop

        if RUBY_VERSION >= "3.2"
          iseq.opt_getconstant_path(names)
          visit(node.value)
          iseq.swap
          iseq.topn(1)
          iseq.swap
          iseq.setconstant(name)
        else
          visit(node.value)
          iseq.dup if last_statement?
          iseq.opt_getconstant_path(names)
          iseq.setconstant(name)
        end
      when Field
        iseq.putnil
        visit(node.target)
        visit(node.value)
        iseq.setn(2)
        iseq.send(:"#{node.target.name.value}=", 1)
        iseq.pop
      when TopConstField
        name = node.target.constant.value.to_sym

        if RUBY_VERSION >= "3.2"
          iseq.putobject(Object)
          visit(node.value)
          iseq.swap
          iseq.topn(1)
          iseq.swap
          iseq.setconstant(name)
        else
          visit(node.value)
          iseq.dup if last_statement?
          iseq.putobject(Object)
          iseq.setconstant(name)
        end
      when VarField
        visit(node.value)
        iseq.dup if last_statement?

        case node.target.value
        when Const
          iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
          iseq.setconstant(node.target.value.value.to_sym)
        when CVar
          iseq.setclassvariable(node.target.value.value.to_sym)
        when GVar
          iseq.setglobal(node.target.value.value.to_sym)
        when Ident
          lookup = visit(node.target)

          if lookup.local.is_a?(YARV::LocalTable::BlockLocal)
            iseq.setblockparam(lookup.index, lookup.level)
          else
            iseq.setlocal(lookup.index, lookup.level)
          end
        when IVar
          iseq.setinstancevariable(node.target.value.value.to_sym)
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
      iseq.getspecial(YARV::VM_SVAR_BACKREF, 2 * node.value[1..].to_i)
    end

    def visit_bare_assoc_hash(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.duphash(compiled)
      else
        visit_all(node.assocs)
      end
    end

    def visit_binary(node)
      case node.operator
      when :"&&"
        visit(node.left)
        iseq.dup

        branchunless = iseq.branchunless(-1)
        iseq.pop

        visit(node.right)
        branchunless.patch!(iseq)
      when :"||"
        visit(node.left)
        iseq.dup

        branchif = iseq.branchif(-1)
        iseq.pop

        visit(node.right)
        branchif.patch!(iseq)
      else
        visit(node.left)
        visit(node.right)
        iseq.send(node.operator, 1)
      end
    end

    def visit_block(node)
      with_child_iseq(iseq.block_child_iseq(node.location)) do
        iseq.event(:RUBY_EVENT_B_CALL)
        visit(node.block_var)
        visit(node.bodystmt)
        iseq.event(:RUBY_EVENT_B_RETURN)
        iseq.leave
      end
    end

    def visit_block_var(node)
      params = node.params

      if params.requireds.length == 1 && params.optionals.empty? &&
           !params.rest && params.posts.empty? && params.keywords.empty? &&
           !params.keyword_rest && !params.block
        iseq.argument_options[:ambiguous_param0] = true
      end

      visit(node.params)

      node.locals.each { |local| iseq.local_table.plain(local.value.to_sym) }
    end

    def visit_blockarg(node)
      iseq.argument_options[:block_start] = iseq.argument_size
      iseq.local_table.block(node.name.value.to_sym)
      iseq.argument_size += 1
    end

    def visit_bodystmt(node)
      visit(node.statements)
    end

    def visit_call(node)
      if node.is_a?(CallNode)
        return(
          visit_call(
            CommandCall.new(
              receiver: node.receiver,
              operator: node.operator,
              message: node.message,
              arguments: node.arguments,
              block: nil,
              location: node.location
            )
          )
        )
      end

      arg_parts = argument_parts(node.arguments)
      argc = arg_parts.length

      # First we're going to check if we're calling a method on an array
      # literal without any arguments. In that case there are some
      # specializations we might be able to perform.
      if argc == 0 && (node.message.is_a?(Ident) || node.message.is_a?(Op))
        case node.receiver
        when ArrayLiteral
          parts = node.receiver.contents&.parts || []

          if parts.none? { |part| part.is_a?(ArgStar) } &&
               RubyVisitor.compile(node.receiver).nil?
            case node.message.value
            when "max"
              visit(node.receiver.contents)
              iseq.opt_newarray_max(parts.length)
              return
            when "min"
              visit(node.receiver.contents)
              iseq.opt_newarray_min(parts.length)
              return
            end
          end
        when StringLiteral
          if RubyVisitor.compile(node.receiver).nil?
            case node.message.value
            when "-@"
              iseq.opt_str_uminus(node.receiver.parts.first.value)
              return
            when "freeze"
              iseq.opt_str_freeze(node.receiver.parts.first.value)
              return
            end
          end
        end
      end

      if node.receiver
        if node.receiver.is_a?(VarRef)
          lookup = iseq.local_variable(node.receiver.value.value.to_sym)

          if lookup.local.is_a?(YARV::LocalTable::BlockLocal)
            iseq.getblockparamproxy(lookup.index, lookup.level)
          else
            visit(node.receiver)
          end
        else
          visit(node.receiver)
        end
      else
        iseq.putself
      end

      branchnil =
        if node.operator&.value == "&."
          iseq.dup
          iseq.branchnil(-1)
        end

      flag = 0

      arg_parts.each do |arg_part|
        case arg_part
        when ArgBlock
          argc -= 1
          flag |= YARV::VM_CALL_ARGS_BLOCKARG
          visit(arg_part)
        when ArgStar
          flag |= YARV::VM_CALL_ARGS_SPLAT
          visit(arg_part)
        when ArgsForward
          flag |= YARV::VM_CALL_ARGS_SPLAT | YARV::VM_CALL_ARGS_BLOCKARG

          lookup = iseq.local_table.find(:*, 0)
          iseq.getlocal(lookup.index, lookup.level)
          iseq.splatarray(arg_parts.length != 1)

          lookup = iseq.local_table.find(:&, 0)
          iseq.getblockparamproxy(lookup.index, lookup.level)
        when BareAssocHash
          flag |= YARV::VM_CALL_KW_SPLAT
          visit(arg_part)
        else
          visit(arg_part)
        end
      end

      block_iseq = visit(node.block) if node.block
      flag |= YARV::VM_CALL_ARGS_SIMPLE if block_iseq.nil? && flag == 0
      flag |= YARV::VM_CALL_FCALL if node.receiver.nil?

      iseq.send(node.message.value.to_sym, argc, flag, block_iseq)
      branchnil.patch!(iseq) if branchnil
    end

    def visit_case(node)
      visit(node.value) if node.value

      clauses = []
      else_clause = nil
      current = node.consequent

      while current
        clauses << current

        if (current = current.consequent).is_a?(Else)
          else_clause = current
          break
        end
      end

      branches =
        clauses.map do |clause|
          visit(clause.arguments)
          iseq.topn(1)
          iseq.send(:===, 1, YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE)
          [clause, iseq.branchif(:label_00)]
        end

      iseq.pop
      else_clause ? visit(else_clause) : iseq.putnil
      iseq.leave

      branches.each_with_index do |(clause, branchif), index|
        iseq.leave if index != 0
        branchif.patch!(iseq)
        iseq.pop
        visit(clause)
      end
    end

    def visit_class(node)
      name = node.constant.constant.value.to_sym
      class_iseq =
        with_child_iseq(iseq.class_child_iseq(name, node.location)) do
          iseq.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          iseq.event(:RUBY_EVENT_END)
          iseq.leave
        end

      flags = YARV::DefineClass::TYPE_CLASS

      case node.constant
      when ConstPathRef
        flags |= YARV::DefineClass::FLAG_SCOPED
        visit(node.constant.parent)
      when ConstRef
        iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
      when TopConstRef
        flags |= YARV::DefineClass::FLAG_SCOPED
        iseq.putobject(Object)
      end

      if node.superclass
        flags |= YARV::DefineClass::FLAG_HAS_SUPERCLASS
        visit(node.superclass)
      else
        iseq.putnil
      end

      iseq.defineclass(name, class_iseq, flags)
    end

    def visit_command(node)
      visit_call(
        CommandCall.new(
          receiver: nil,
          operator: nil,
          message: node.message,
          arguments: node.arguments,
          block: node.block,
          location: node.location
        )
      )
    end

    def visit_command_call(node)
      visit_call(
        CommandCall.new(
          receiver: node.receiver,
          operator: node.operator,
          message: node.message,
          arguments: node.arguments,
          block: node.block,
          location: node.location
        )
      )
    end

    def visit_const_path_field(node)
      visit(node.parent)
    end

    def visit_const_path_ref(node)
      names = constant_names(node)
      iseq.opt_getconstant_path(names)
    end

    def visit_def(node)
      name = node.name.value.to_sym
      method_iseq = iseq.method_child_iseq(name.to_s, node.location)

      with_child_iseq(method_iseq) do
        visit(node.params) if node.params
        iseq.event(:RUBY_EVENT_CALL)
        visit(node.bodystmt)
        iseq.event(:RUBY_EVENT_RETURN)
        iseq.leave
      end

      if node.target
        visit(node.target)
        iseq.definesmethod(name, method_iseq)
      else
        iseq.definemethod(name, method_iseq)
      end

      iseq.putobject(name)
    end

    def visit_defined(node)
      case node.value
      when Assign
        # If we're assigning to a local variable, then we need to make sure
        # that we put it into the local table.
        if node.value.target.is_a?(VarField) &&
             node.value.target.value.is_a?(Ident)
          iseq.local_table.plain(node.value.target.value.value.to_sym)
        end

        iseq.putobject("assignment")
      when VarRef
        value = node.value.value
        name = value.value.to_sym

        case value
        when Const
          iseq.putnil
          iseq.defined(YARV::Defined::CONST, name, "constant")
        when CVar
          iseq.putnil
          iseq.defined(YARV::Defined::CVAR, name, "class variable")
        when GVar
          iseq.putnil
          iseq.defined(YARV::Defined::GVAR, name, "global-variable")
        when Ident
          iseq.putobject("local-variable")
        when IVar
          iseq.putnil
          iseq.defined(YARV::Defined::IVAR, name, "instance-variable")
        when Kw
          case name
          when :false
            iseq.putobject("false")
          when :nil
            iseq.putobject("nil")
          when :self
            iseq.putobject("self")
          when :true
            iseq.putobject("true")
          end
        end
      when VCall
        iseq.putself

        name = node.value.value.value.to_sym
        iseq.defined(YARV::Defined::FUNC, name, "method")
      when YieldNode
        iseq.putnil
        iseq.defined(YARV::Defined::YIELD, false, "yield")
      when ZSuper
        iseq.putnil
        iseq.defined(YARV::Defined::ZSUPER, false, "super")
      else
        iseq.putobject("expression")
      end
    end

    def visit_dyna_symbol(node)
      if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
        iseq.putobject(node.parts.first.value.to_sym)
      end
    end

    def visit_else(node)
      visit(node.statements)
      iseq.pop unless last_statement?
    end

    def visit_elsif(node)
      visit_if(
        IfNode.new(
          predicate: node.predicate,
          statements: node.statements,
          consequent: node.consequent,
          location: node.location
        )
      )
    end

    def visit_field(node)
      visit(node.parent)
    end

    def visit_float(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_for(node)
      visit(node.collection)

      name = node.index.value.value.to_sym
      iseq.local_table.plain(name)

      block_iseq =
        with_child_iseq(iseq.block_child_iseq(node.statements.location)) do
          iseq.argument_options[:lead_num] ||= 0
          iseq.argument_options[:lead_num] += 1
          iseq.argument_options[:ambiguous_param0] = true

          iseq.argument_size += 1
          iseq.local_table.plain(2)

          iseq.getlocal(0, 0)

          local_variable = iseq.local_variable(name)
          iseq.setlocal(local_variable.index, local_variable.level)

          iseq.event(:RUBY_EVENT_B_CALL)
          iseq.nop

          visit(node.statements)
          iseq.event(:RUBY_EVENT_B_RETURN)
          iseq.leave
        end

      iseq.send(:each, 0, 0, block_iseq)
    end

    def visit_hash(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.duphash(compiled)
      else
        visit_all(node.assocs)
        iseq.newhash(node.assocs.length * 2)
      end
    end

    def visit_heredoc(node)
      if node.beginning.value.end_with?("`")
        visit_xstring_literal(node)
      elsif node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
        visit(node.parts.first)
      else
        length = visit_string_parts(node)
        iseq.concatstrings(length)
      end
    end

    def visit_if(node)
      if node.predicate.is_a?(RangeNode)
        iseq.getspecial(YARV::VM_SVAR_FLIPFLOP_START, 0)
        branchif = iseq.branchif(-1)

        visit(node.predicate.left)
        branchunless_true = iseq.branchunless(-1)

        iseq.putobject(true)
        iseq.setspecial(YARV::VM_SVAR_FLIPFLOP_START)
        branchif.patch!(iseq)

        visit(node.predicate.right)
        branchunless_false = iseq.branchunless(-1)

        iseq.putobject(false)
        iseq.setspecial(YARV::VM_SVAR_FLIPFLOP_START)
        branchunless_false.patch!(iseq)

        visit(node.statements)
        iseq.leave
        branchunless_true.patch!(iseq)
        iseq.putnil
      else
        visit(node.predicate)
        branchunless = iseq.branchunless(-1)
        visit(node.statements)

        if last_statement?
          iseq.leave
          branchunless.patch!(iseq)

          node.consequent ? visit(node.consequent) : iseq.putnil
        else
          iseq.pop

          if node.consequent
            jump = iseq.jump(-1)
            branchunless.patch!(iseq)
            visit(node.consequent)
            jump[1] = iseq.label
          else
            branchunless.patch!(iseq)
          end
        end
      end
    end

    def visit_if_op(node)
      visit_if(
        IfNode.new(
          predicate: node.predicate,
          statements: node.truthy,
          consequent:
            Else.new(
              keyword: Kw.new(value: "else", location: Location.default),
              statements: node.falsy,
              location: Location.default
            ),
          location: Location.default
        )
      )
    end

    def visit_imaginary(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_int(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_kwrest_param(node)
      iseq.argument_options[:kwrest] = iseq.argument_size
      iseq.argument_size += 1
      iseq.local_table.plain(node.name.value.to_sym)
    end

    def visit_label(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_lambda(node)
      lambda_iseq =
        with_child_iseq(iseq.block_child_iseq(node.location)) do
          iseq.event(:RUBY_EVENT_B_CALL)
          visit(node.params)
          visit(node.statements)
          iseq.event(:RUBY_EVENT_B_RETURN)
          iseq.leave
        end

      iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
      iseq.send(:lambda, 0, YARV::VM_CALL_FCALL, lambda_iseq)
    end

    def visit_lambda_var(node)
      visit_block_var(node)
    end

    def visit_massign(node)
      visit(node.value)
      iseq.dup
      visit(node.target)
    end

    def visit_method_add_block(node)
      visit_call(
        CommandCall.new(
          receiver: node.call.receiver,
          operator: node.call.operator,
          message: node.call.message,
          arguments: node.call.arguments,
          block: node.block,
          location: node.location
        )
      )
    end

    def visit_mlhs(node)
      lookups = []
      node.parts.each do |part|
        case part
        when VarField
          lookups << visit(part)
        end
      end

      iseq.expandarray(lookups.length, 0)
      lookups.each { |lookup| iseq.setlocal(lookup.index, lookup.level) }
    end

    def visit_module(node)
      name = node.constant.constant.value.to_sym
      module_iseq =
        with_child_iseq(iseq.module_child_iseq(name, node.location)) do
          iseq.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          iseq.event(:RUBY_EVENT_END)
          iseq.leave
        end

      flags = YARV::DefineClass::TYPE_MODULE

      case node.constant
      when ConstPathRef
        flags |= YARV::DefineClass::FLAG_SCOPED
        visit(node.constant.parent)
      when ConstRef
        iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
      when TopConstRef
        flags |= YARV::DefineClass::FLAG_SCOPED
        iseq.putobject(Object)
      end

      iseq.putnil
      iseq.defineclass(name, module_iseq, flags)
    end

    def visit_mrhs(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.duparray(compiled)
      else
        visit_all(node.parts)
        iseq.newarray(node.parts.length)
      end
    end

    def visit_not(node)
      visit(node.statement)
      iseq.send(:!, 0)
    end

    def visit_opassign(node)
      flag = YARV::VM_CALL_ARGS_SIMPLE
      if node.target.is_a?(ConstPathField) || node.target.is_a?(TopConstField)
        flag |= YARV::VM_CALL_FCALL
      end

      case (operator = node.operator.value.chomp("=").to_sym)
      when :"&&"
        branchunless = nil

        with_opassign(node) do
          iseq.dup
          branchunless = iseq.branchunless(-1)
          iseq.pop
          visit(node.value)
        end

        case node.target
        when ARefField
          iseq.leave
          branchunless.patch!(iseq)
          iseq.setn(3)
          iseq.adjuststack(3)
        when ConstPathField, TopConstField
          branchunless.patch!(iseq)
          iseq.swap
          iseq.pop
        else
          branchunless.patch!(iseq)
        end
      when :"||"
        if node.target.is_a?(ConstPathField) || node.target.is_a?(TopConstField)
          opassign_defined(node)
          iseq.swap
          iseq.pop
        elsif node.target.is_a?(VarField) &&
              [Const, CVar, GVar].include?(node.target.value.class)
          opassign_defined(node)
        else
          branchif = nil

          with_opassign(node) do
            iseq.dup
            branchif = iseq.branchif(-1)
            iseq.pop
            visit(node.value)
          end

          if node.target.is_a?(ARefField)
            iseq.leave
            branchif.patch!(iseq)
            iseq.setn(3)
            iseq.adjuststack(3)
          else
            branchif.patch!(iseq)
          end
        end
      else
        with_opassign(node) do
          visit(node.value)
          iseq.send(operator, 1, flag)
        end
      end
    end

    def visit_params(node)
      argument_options = iseq.argument_options

      if node.requireds.any?
        argument_options[:lead_num] = 0

        node.requireds.each do |required|
          iseq.local_table.plain(required.value.to_sym)
          iseq.argument_size += 1
          argument_options[:lead_num] += 1
        end
      end

      node.optionals.each do |(optional, value)|
        index = iseq.local_table.size
        name = optional.value.to_sym

        iseq.local_table.plain(name)
        iseq.argument_size += 1

        argument_options[:opt] = [iseq.label] unless argument_options.key?(:opt)

        visit(value)
        iseq.setlocal(index, 0)
        iseq.argument_options[:opt] << iseq.label
      end

      visit(node.rest) if node.rest

      if node.posts.any?
        argument_options[:post_start] = iseq.argument_size
        argument_options[:post_num] = 0

        node.posts.each do |post|
          iseq.local_table.plain(post.value.to_sym)
          iseq.argument_size += 1
          argument_options[:post_num] += 1
        end
      end

      if node.keywords.any?
        argument_options[:kwbits] = 0
        argument_options[:keyword] = []

        keyword_bits_name = node.keyword_rest ? 3 : 2
        iseq.argument_size += 1
        keyword_bits_index = iseq.local_table.locals.size + node.keywords.size

        node.keywords.each_with_index do |(keyword, value), keyword_index|
          name = keyword.value.chomp(":").to_sym
          index = iseq.local_table.size

          iseq.local_table.plain(name)
          iseq.argument_size += 1
          argument_options[:kwbits] += 1

          if value.nil?
            argument_options[:keyword] << name
          elsif (compiled = RubyVisitor.compile(value))
            argument_options[:keyword] << [name, compiled]
          else
            argument_options[:keyword] << [name]
            iseq.checkkeyword(keyword_bits_index, keyword_index)
            branchif = iseq.branchif(-1)
            visit(value)
            iseq.setlocal(index, 0)
            branchif.patch!(iseq)
          end
        end

        iseq.local_table.plain(keyword_bits_name)
      end

      if node.keyword_rest.is_a?(ArgsForward)
        iseq.local_table.plain(:*)
        iseq.local_table.plain(:&)

        iseq.argument_options[:rest_start] = iseq.argument_size
        iseq.argument_options[:block_start] = iseq.argument_size + 1

        iseq.argument_size += 2
      elsif node.keyword_rest
        visit(node.keyword_rest)
      end

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

      preexes = []
      statements = []

      node.statements.body.each do |statement|
        case statement
        when Comment, EmbDoc, EndContent, VoidStmt
          # ignore
        when BEGINBlock
          preexes << statement
        else
          statements << statement
        end
      end

      top_iseq =
        YARV::InstructionSequence.new(
          :top,
          "<compiled>",
          nil,
          node.location,
          frozen_string_literal: frozen_string_literal,
          operands_unification: operands_unification,
          specialized_instruction: specialized_instruction
        )

      with_child_iseq(top_iseq) do
        visit_all(preexes)

        if statements.empty?
          iseq.putnil
        else
          *statements, last_statement = statements
          visit_all(statements)
          with_last_statement { visit(last_statement) }
        end

        iseq.leave
      end
    end

    def visit_qsymbols(node)
      iseq.duparray(node.accept(RubyVisitor.new))
    end

    def visit_qwords(node)
      if frozen_string_literal
        iseq.duparray(node.accept(RubyVisitor.new))
      else
        visit_all(node.elements)
        iseq.newarray(node.elements.length)
      end
    end

    def visit_range(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.putobject(compiled)
      else
        visit(node.left)
        visit(node.right)
        iseq.newrange(node.operator.value == ".." ? 0 : 1)
      end
    end

    def visit_rational(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_regexp_literal(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.putobject(compiled)
      else
        flags = RubyVisitor.new.visit_regexp_literal_flags(node)
        length = visit_string_parts(node)
        iseq.toregexp(flags, length)
      end
    end

    def visit_rest_param(node)
      iseq.local_table.plain(node.name.value.to_sym)
      iseq.argument_options[:rest_start] = iseq.argument_size
      iseq.argument_size += 1
    end

    def visit_sclass(node)
      visit(node.target)
      iseq.putnil

      singleton_iseq =
        with_child_iseq(iseq.singleton_class_child_iseq(node.location)) do
          iseq.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          iseq.event(:RUBY_EVENT_END)
          iseq.leave
        end

      iseq.defineclass(
        :singletonclass,
        singleton_iseq,
        YARV::DefineClass::TYPE_SINGLETON_CLASS
      )
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

      statements.empty? ? iseq.putnil : visit_all(statements)
    end

    def visit_string_concat(node)
      value = node.left.parts.first.value + node.right.parts.first.value

      visit_string_literal(
        StringLiteral.new(
          parts: [TStringContent.new(value: value, location: node.location)],
          quote: node.left.quote,
          location: node.location
        )
      )
    end

    def visit_string_embexpr(node)
      visit(node.statements)
    end

    def visit_string_literal(node)
      if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
        visit(node.parts.first)
      else
        length = visit_string_parts(node)
        iseq.concatstrings(length)
      end
    end

    def visit_super(node)
      iseq.putself
      visit(node.arguments)
      iseq.invokesuper(
        nil,
        argument_parts(node.arguments).length,
        YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE | YARV::VM_CALL_SUPER,
        nil
      )
    end

    def visit_symbol_literal(node)
      iseq.putobject(node.accept(RubyVisitor.new))
    end

    def visit_symbols(node)
      if (compiled = RubyVisitor.compile(node))
        iseq.duparray(compiled)
      else
        node.elements.each do |element|
          if element.parts.length == 1 &&
               element.parts.first.is_a?(TStringContent)
            iseq.putobject(element.parts.first.value.to_sym)
          else
            length = visit_string_parts(element)
            iseq.concatstrings(length)
            iseq.intern
          end
        end

        iseq.newarray(node.elements.length)
      end
    end

    def visit_top_const_ref(node)
      iseq.opt_getconstant_path(constant_names(node))
    end

    def visit_tstring_content(node)
      if frozen_string_literal
        iseq.putobject(node.accept(RubyVisitor.new))
      else
        iseq.putstring(node.accept(RubyVisitor.new))
      end
    end

    def visit_unary(node)
      method_id =
        case node.operator
        when "+", "-"
          "#{node.operator}@"
        else
          node.operator
        end

      visit_call(
        CommandCall.new(
          receiver: node.statement,
          operator: nil,
          message: Ident.new(value: method_id, location: Location.default),
          arguments: nil,
          block: nil,
          location: Location.default
        )
      )
    end

    def visit_undef(node)
      node.symbols.each_with_index do |symbol, index|
        iseq.pop if index != 0
        iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
        iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CBASE)
        visit(symbol)
        iseq.send(:"core#undef_method", 2)
      end
    end

    def visit_unless(node)
      visit(node.predicate)
      branchunless = iseq.branchunless(-1)
      node.consequent ? visit(node.consequent) : iseq.putnil

      if last_statement?
        iseq.leave
        branchunless.patch!(iseq)

        visit(node.statements)
      else
        iseq.pop

        if node.consequent
          jump = iseq.jump(-1)
          branchunless.patch!(iseq)
          visit(node.consequent)
          jump[1] = iseq.label
        else
          branchunless.patch!(iseq)
        end
      end
    end

    def visit_until(node)
      jumps = []

      jumps << iseq.jump(-1)
      iseq.putnil
      iseq.pop
      jumps << iseq.jump(-1)

      label = iseq.label
      visit(node.statements)
      iseq.pop
      jumps.each { |jump| jump[1] = iseq.label }

      visit(node.predicate)
      iseq.branchunless(label)
      iseq.putnil if last_statement?
    end

    def visit_var_field(node)
      case node.value
      when CVar, IVar
        name = node.value.value.to_sym
        iseq.inline_storage_for(name)
      when Ident
        name = node.value.value.to_sym

        if (local_variable = iseq.local_variable(name))
          local_variable
        else
          iseq.local_table.plain(name)
          iseq.local_variable(name)
        end
      end
    end

    def visit_var_ref(node)
      case node.value
      when Const
        iseq.opt_getconstant_path(constant_names(node))
      when CVar
        name = node.value.value.to_sym
        iseq.getclassvariable(name)
      when GVar
        iseq.getglobal(node.value.value.to_sym)
      when Ident
        lookup = iseq.local_variable(node.value.value.to_sym)

        case lookup.local
        when YARV::LocalTable::BlockLocal
          iseq.getblockparam(lookup.index, lookup.level)
        when YARV::LocalTable::PlainLocal
          iseq.getlocal(lookup.index, lookup.level)
        end
      when IVar
        name = node.value.value.to_sym
        iseq.getinstancevariable(name)
      when Kw
        case node.value.value
        when "false"
          iseq.putobject(false)
        when "nil"
          iseq.putnil
        when "self"
          iseq.putself
        when "true"
          iseq.putobject(true)
        end
      end
    end

    def visit_vcall(node)
      iseq.putself

      flag =
        YARV::VM_CALL_FCALL | YARV::VM_CALL_VCALL | YARV::VM_CALL_ARGS_SIMPLE
      iseq.send(node.value.value.to_sym, 0, flag)
    end

    def visit_when(node)
      visit(node.statements)
    end

    def visit_while(node)
      jumps = []

      jumps << iseq.jump(-1)
      iseq.putnil
      iseq.pop
      jumps << iseq.jump(-1)

      label = iseq.label
      visit(node.statements)
      iseq.pop
      jumps.each { |jump| jump[1] = iseq.label }

      visit(node.predicate)
      iseq.branchif(label)
      iseq.putnil if last_statement?
    end

    def visit_word(node)
      if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
        visit(node.parts.first)
      else
        length = visit_string_parts(node)
        iseq.concatstrings(length)
      end
    end

    def visit_words(node)
      if frozen_string_literal && (compiled = RubyVisitor.compile(node))
        iseq.duparray(compiled)
      else
        visit_all(node.elements)
        iseq.newarray(node.elements.length)
      end
    end

    def visit_xstring_literal(node)
      iseq.putself
      length = visit_string_parts(node)
      iseq.concatstrings(node.parts.length) if length > 1
      iseq.send(:`, 1, YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE)
    end

    def visit_yield(node)
      parts = argument_parts(node.arguments)
      visit_all(parts)
      iseq.invokeblock(nil, parts.length)
    end

    def visit_zsuper(_node)
      iseq.putself
      iseq.invokesuper(
        nil,
        0,
        YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE | YARV::VM_CALL_SUPER |
          YARV::VM_CALL_ZSUPER,
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
        if node.arguments.is_a?(ArgsForward)
          [node.arguments]
        else
          node.arguments.parts
        end
      when Paren
        node.contents.parts
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

        iseq.dup
        iseq.defined(YARV::Defined::CONST_FROM, name, true)
      when TopConstField
        name = node.target.constant.value.to_sym

        iseq.putobject(Object)
        iseq.dup
        iseq.defined(YARV::Defined::CONST_FROM, name, true)
      when VarField
        name = node.target.value.value.to_sym
        iseq.putnil

        case node.target.value
        when Const
          iseq.defined(YARV::Defined::CONST, name, true)
        when CVar
          iseq.defined(YARV::Defined::CVAR, name, true)
        when GVar
          iseq.defined(YARV::Defined::GVAR, name, true)
        end
      end

      branchunless = iseq.branchunless(-1)

      case node.target
      when ConstPathField, TopConstField
        iseq.dup
        iseq.putobject(true)
        iseq.getconstant(name)
      when VarField
        case node.target.value
        when Const
          iseq.opt_getconstant_path(constant_names(node.target))
        when CVar
          iseq.getclassvariable(name)
        when GVar
          iseq.getglobal(name)
        end
      end

      iseq.dup
      branchif = iseq.branchif(-1)
      iseq.pop

      branchunless.patch!(iseq)
      visit(node.value)

      case node.target
      when ConstPathField, TopConstField
        iseq.dupn(2)
        iseq.swap
        iseq.setconstant(name)
      when VarField
        iseq.dup

        case node.target.value
        when Const
          iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
          iseq.setconstant(name)
        when CVar
          iseq.setclassvariable(name)
        when GVar
          iseq.setglobal(name)
        end
      end

      branchif.patch!(iseq)
    end

    # Whenever a value is interpolated into a string-like structure, these
    # three instructions are pushed.
    def push_interpolate
      iseq.dup
      iseq.objtostring(
        :to_s,
        0,
        YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE
      )
      iseq.anytostring
    end

    # There are a lot of nodes in the AST that act as contains of parts of
    # strings. This includes things like string literals, regular expressions,
    # heredocs, etc. This method will visit all the parts of a string within
    # those containers.
    def visit_string_parts(node)
      length = 0

      unless node.parts.first.is_a?(TStringContent)
        iseq.putobject("")
        length += 1
      end

      node.parts.each do |part|
        case part
        when StringDVar
          visit(part.variable)
          push_interpolate
        when StringEmbExpr
          visit(part)
          push_interpolate
        when TStringContent
          iseq.putobject(part.accept(RubyVisitor.new))
        end

        length += 1
      end

      length
    end

    # The current instruction sequence that we're compiling is always stored
    # on the compiler. When we descend into a node that has its own
    # instruction sequence, this method can be called to temporarily set the
    # new value of the instruction sequence, yield, and then set it back.
    def with_child_iseq(child_iseq)
      parent_iseq = iseq

      begin
        @iseq = child_iseq
        yield
        child_iseq
      ensure
        @iseq = parent_iseq
      end
    end

    # When we're compiling the last statement of a set of statements within a
    # scope, the instructions sometimes change from pops to leaves. These
    # kinds of peephole optimizations can reduce the overall number of
    # instructions. Therefore, we keep track of whether we're compiling the
    # last statement of a scope and allow visit methods to query that
    # information.
    def with_last_statement
      previous = @last_statement
      @last_statement = true

      begin
        yield
      ensure
        @last_statement = previous
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
        iseq.putnil
        visit(node.target.collection)
        visit(node.target.index)

        iseq.dupn(2)
        iseq.send(:[], 1)

        yield

        iseq.setn(3)
        iseq.send(:[]=, 2)
        iseq.pop
      when ConstPathField
        name = node.target.constant.value.to_sym

        visit(node.target.parent)
        iseq.dup
        iseq.putobject(true)
        iseq.getconstant(name)

        yield

        if node.operator.value == "&&="
          iseq.dupn(2)
        else
          iseq.swap
          iseq.topn(1)
        end

        iseq.swap
        iseq.setconstant(name)
      when TopConstField
        name = node.target.constant.value.to_sym

        iseq.putobject(Object)
        iseq.dup
        iseq.putobject(true)
        iseq.getconstant(name)

        yield

        if node.operator.value == "&&="
          iseq.dupn(2)
        else
          iseq.swap
          iseq.topn(1)
        end

        iseq.swap
        iseq.setconstant(name)
      when VarField
        case node.target.value
        when Const
          names = constant_names(node.target)
          iseq.opt_getconstant_path(names)

          yield

          iseq.dup
          iseq.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
          iseq.setconstant(names.last)
        when CVar
          name = node.target.value.value.to_sym
          iseq.getclassvariable(name)

          yield

          iseq.dup
          iseq.setclassvariable(name)
        when GVar
          name = node.target.value.value.to_sym
          iseq.getglobal(name)

          yield

          iseq.dup
          iseq.setglobal(name)
        when Ident
          local_variable = visit(node.target)
          iseq.getlocal(local_variable.index, local_variable.level)

          yield

          iseq.dup
          iseq.setlocal(local_variable.index, local_variable.level)
        when IVar
          name = node.target.value.value.to_sym
          iseq.getinstancevariable(name)

          yield

          iseq.dup
          iseq.setinstancevariable(name)
        end
      end
    end
  end
end
