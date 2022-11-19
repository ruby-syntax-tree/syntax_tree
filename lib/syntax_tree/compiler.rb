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

    def visit_BEGIN(node)
      visit(node.statements)
    end

    def visit_CHAR(node)
      if frozen_string_literal
        builder.putobject(node.value[1..])
      else
        builder.putstring(node.value[1..])
      end
    end

    def visit_END(node)
      name = "block in #{current_iseq.name}"
      once_iseq =
        with_instruction_sequence(:block, name, current_iseq, node) do
          postexe_iseq =
            with_instruction_sequence(:block, name, current_iseq, node) do
              *statements, last_statement = node.statements.body
              visit_all(statements)
              with_last_statement { visit(last_statement) }
              builder.leave
            end

          builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
          builder.send(:"core#set_postexe", 0, YARV::VM_CALL_FCALL, postexe_iseq)
          builder.leave
        end

      builder.once(once_iseq, current_iseq.inline_storage)
      builder.pop
    end

    def visit_alias(node)
      builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
      builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CBASE)
      visit(node.left)
      visit(node.right)
      builder.send(:"core#set_method_alias", 3, YARV::VM_CALL_ARGS_SIMPLE)
    end

    def visit_aref(node)
      visit(node.collection)
      visit(node.index)
      builder.send(:[], 1, YARV::VM_CALL_ARGS_SIMPLE)
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
      if (compiled = RubyVisitor.compile(node))
        builder.duparray(compiled)
      else
        length = 0

        node.contents.parts.each do |part|
          if part.is_a?(ArgStar)
            if length > 0
              builder.newarray(length)
              length = 0
            end

            visit(part.value)
            builder.concatarray
          else
            visit(part)
            length += 1
          end
        end

        builder.newarray(length) if length > 0
        if length > 0 && length != node.contents.parts.length
          builder.concatarray
        end
      end
    end

    def visit_assign(node)
      case node.target
      when ARefField
        builder.putnil
        visit(node.target.collection)
        visit(node.target.index)
        visit(node.value)
        builder.setn(3)
        builder.send(:[]=, 2, YARV::VM_CALL_ARGS_SIMPLE)
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
        builder.send(:"#{node.target.name.value}=", 1, YARV::VM_CALL_ARGS_SIMPLE)
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
          builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
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
      if (compiled = RubyVisitor.compile(node))
        builder.duphash(compiled)
      else
        visit_all(node.assocs)
      end
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
        builder.send(node.operator, 1, YARV::VM_CALL_ARGS_SIMPLE)
      end
    end

    def visit_block(node)
      with_instruction_sequence(
        :block,
        "block in #{current_iseq.name}",
        current_iseq,
        node
      ) do
        builder.event(:RUBY_EVENT_B_CALL)
        visit(node.block_var)
        visit(node.bodystmt)
        builder.event(:RUBY_EVENT_B_RETURN)
        builder.leave
      end
    end

    def visit_block_var(node)
      params = node.params

      if params.requireds.length == 1 && params.optionals.empty? &&
            !params.rest && params.posts.empty? && params.keywords.empty? &&
            !params.keyword_rest && !params.block
        current_iseq.argument_options[:ambiguous_param0] = true
      end

      visit(node.params)

      node.locals.each do |local|
        current_iseq.local_table.plain(local.value.to_sym)
      end
    end

    def visit_blockarg(node)
      current_iseq.argument_options[:block_start] = current_iseq.argument_size
      current_iseq.local_table.block(node.name.value.to_sym)
      current_iseq.argument_size += 1
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
              builder.opt_newarray_max(parts.length)
              return
            when "min"
              visit(node.receiver.contents)
              builder.opt_newarray_min(parts.length)
              return
            end
          end
        when StringLiteral
          if RubyVisitor.compile(node.receiver).nil?
            case node.message.value
            when "-@"
              builder.opt_str_uminus(node.receiver.parts.first.value)
              return
            when "freeze"
              builder.opt_str_freeze(node.receiver.parts.first.value)
              return
            end
          end
        end
      end

      if node.receiver
        if node.receiver.is_a?(VarRef)
          lookup = current_iseq.local_variable(node.receiver.value.value.to_sym)

          if lookup.local.is_a?(YARV::LocalTable::BlockLocal)
            builder.getblockparamproxy(lookup.index, lookup.level)
          else
            visit(node.receiver)
          end
        else
          visit(node.receiver)
        end
      else
        builder.putself
      end

      branchnil =
        if node.operator&.value == "&."
          builder.dup
          builder.branchnil(-1)
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

          lookup = current_iseq.local_table.find(:*, 0)
          builder.getlocal(lookup.index, lookup.level)
          builder.splatarray(arg_parts.length != 1)

          lookup = current_iseq.local_table.find(:&, 0)
          builder.getblockparamproxy(lookup.index, lookup.level)
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

      builder.send(node.message.value.to_sym, argc, flag, block_iseq)
      branchnil[1] = builder.label if branchnil
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
          builder.topn(1)
          builder.send(:===, 1, YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE)
          [clause, builder.branchif(:label_00)]
        end

      builder.pop

      else_clause ? visit(else_clause) : builder.putnil

      builder.leave

      branches.each_with_index do |(clause, branchif), index|
        builder.leave if index != 0
        branchif[1] = builder.label
        builder.pop
        visit(clause)
      end
    end

    def visit_class(node)
      name = node.constant.constant.value.to_sym
      class_iseq =
        with_instruction_sequence(
          :class,
          "<class:#{name}>",
          current_iseq,
          node
        ) do
          builder.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          builder.event(:RUBY_EVENT_END)
          builder.leave
        end

      flags = YARV::VM_DEFINECLASS_TYPE_CLASS

      case node.constant
      when ConstPathRef
        flags |= YARV::VM_DEFINECLASS_FLAG_SCOPED
        visit(node.constant.parent)
      when ConstRef
        builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
      when TopConstRef
        flags |= YARV::VM_DEFINECLASS_FLAG_SCOPED
        builder.putobject(Object)
      end

      if node.superclass
        flags |= YARV::VM_DEFINECLASS_FLAG_HAS_SUPERCLASS
        visit(node.superclass)
      else
        builder.putnil
      end

      builder.defineclass(name, class_iseq, flags)
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
          builder.event(:RUBY_EVENT_CALL)
          visit(node.bodystmt)
          builder.event(:RUBY_EVENT_RETURN)
          builder.leave
        end

      name = node.name.value.to_sym

      if node.target
        visit(node.target)
        builder.definesmethod(name, method_iseq)
      else
        builder.definemethod(name, method_iseq)
      end

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
          builder.defined(YARV::DEFINED_CONST, name, "constant")
        when CVar
          builder.putnil
          builder.defined(YARV::DEFINED_CVAR, name, "class variable")
        when GVar
          builder.putnil
          builder.defined(YARV::DEFINED_GVAR, name, "global-variable")
        when Ident
          builder.putobject("local-variable")
        when IVar
          builder.putnil
          builder.defined(YARV::DEFINED_IVAR, name, "instance-variable")
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
        builder.defined(YARV::DEFINED_FUNC, name, "method")
      when YieldNode
        builder.putnil
        builder.defined(YARV::DEFINED_YIELD, false, "yield")
      when ZSuper
        builder.putnil
        builder.defined(YARV::DEFINED_ZSUPER, false, "super")
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

          builder.event(:RUBY_EVENT_B_CALL)
          builder.nop

          visit(node.statements)
          builder.event(:RUBY_EVENT_B_RETURN)
          builder.leave
        end

      builder.send(:each, 0, 0, block_iseq)
    end

    def visit_hash(node)
      if (compiled = RubyVisitor.compile(node))
        builder.duphash(compiled)
      else
        visit_all(node.assocs)
        builder.newhash(node.assocs.length * 2)
      end
    end

    def visit_heredoc(node)
      if node.beginning.value.end_with?("`")
        visit_xstring_literal(node)
      elsif node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
        visit(node.parts.first)
      else
        length = visit_string_parts(node)
        builder.concatstrings(length)
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

    def visit_lambda(node)
      lambda_iseq =
        with_instruction_sequence(
          :block,
          "block in #{current_iseq.name}",
          current_iseq,
          node
        ) do
          builder.event(:RUBY_EVENT_B_CALL)
          visit(node.params)
          visit(node.statements)
          builder.event(:RUBY_EVENT_B_RETURN)
          builder.leave
        end

      builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
      builder.send(:lambda, 0, YARV::VM_CALL_FCALL, lambda_iseq)
    end

    def visit_lambda_var(node)
      visit_block_var(node)
    end

    def visit_massign(node)
      visit(node.value)
      builder.dup
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

      builder.expandarray(lookups.length, 0)

      lookups.each { |lookup| builder.setlocal(lookup.index, lookup.level) }
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
          builder.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          builder.event(:RUBY_EVENT_END)
          builder.leave
        end

      flags = YARV::VM_DEFINECLASS_TYPE_MODULE

      case node.constant
      when ConstPathRef
        flags |= YARV::VM_DEFINECLASS_FLAG_SCOPED
        visit(node.constant.parent)
      when ConstRef
        builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
      when TopConstRef
        flags |= YARV::VM_DEFINECLASS_FLAG_SCOPED
        builder.putobject(Object)
      end

      builder.putnil
      builder.defineclass(name, module_iseq, flags)
    end

    def visit_mrhs(node)
      if (compiled = RubyVisitor.compile(node))
        builder.duparray(compiled)
      else
        visit_all(node.parts)
        builder.newarray(node.parts.length)
      end
    end

    def visit_not(node)
      visit(node.statement)
      builder.send(:!, 0, YARV::VM_CALL_ARGS_SIMPLE)
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
          elsif (compiled = RubyVisitor.compile(value))
            compiled = value.accept(RubyVisitor.new)
            argument_options[:keyword] << [name, compiled]
          else
            argument_options[:keyword] << [name]
            checkkeywords << builder.checkkeyword(-1, keyword_index)
            branchif = builder.branchif(-1)
            visit(value)
            builder.setlocal(index, 0)
            branchif[1] = builder.label
          end
        end

        name = node.keyword_rest ? 3 : 2
        current_iseq.argument_size += 1
        current_iseq.local_table.plain(name)

        lookup = current_iseq.local_table.find(name, 0)
        checkkeywords.each { |checkkeyword| checkkeyword[1] = lookup.index }
      end

      if node.keyword_rest.is_a?(ArgsForward)
        current_iseq.local_table.plain(:*)
        current_iseq.local_table.plain(:&)

        current_iseq.argument_options[
          :rest_start
        ] = current_iseq.argument_size
        current_iseq.argument_options[
          :block_start
        ] = current_iseq.argument_size + 1

        current_iseq.argument_size += 2
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

      with_instruction_sequence(:top, "<compiled>", nil, node) do
        visit_all(preexes)

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
      if (compiled = RubyVisitor.compile(node))
        builder.putobject(compiled)
      else
        visit(node.left)
        visit(node.right)
        builder.newrange(node.operator.value == ".." ? 0 : 1)
      end
    end

    def visit_rational(node)
      builder.putobject(node.accept(RubyVisitor.new))
    end

    def visit_regexp_literal(node)
      if (compiled = RubyVisitor.compile(node))
        builder.putobject(compiled)
      else
        flags = RubyVisitor.new.visit_regexp_literal_flags(node)
        length = visit_string_parts(node)
        builder.toregexp(flags, length)
      end
    end

    def visit_rest_param(node)
      current_iseq.local_table.plain(node.name.value.to_sym)
      current_iseq.argument_options[:rest_start] = current_iseq.argument_size
      current_iseq.argument_size += 1
    end

    def visit_sclass(node)
      visit(node.target)
      builder.putnil

      singleton_iseq =
        with_instruction_sequence(
          :class,
          "singleton class",
          current_iseq,
          node
        ) do
          builder.event(:RUBY_EVENT_CLASS)
          visit(node.bodystmt)
          builder.event(:RUBY_EVENT_END)
          builder.leave
        end

      builder.defineclass(
        :singletonclass,
        singleton_iseq,
        YARV::VM_DEFINECLASS_TYPE_SINGLETON_CLASS
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
        length = visit_string_parts(node)
        builder.concatstrings(length)
      end
    end

    def visit_super(node)
      builder.putself
      visit(node.arguments)
      builder.invokesuper(
        nil,
        argument_parts(node.arguments).length,
        YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE | YARV::VM_CALL_SUPER,
        nil
      )
    end

    def visit_symbol_literal(node)
      builder.putobject(node.accept(RubyVisitor.new))
    end

    def visit_symbols(node)
      if (compiled = RubyVisitor.compile(node))
        builder.duparray(compiled)
      else
        node.elements.each do |element|
          if element.parts.length == 1 &&
                element.parts.first.is_a?(TStringContent)
            builder.putobject(element.parts.first.value.to_sym)
          else
            length = visit_string_parts(element)
            builder.concatstrings(length)
            builder.intern
          end
        end

        builder.newarray(node.elements.length)
      end
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
        builder.pop if index != 0
        builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_VMCORE)
        builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CBASE)
        visit(symbol)
        builder.send(:"core#undef_method", 2, YARV::VM_CALL_ARGS_SIMPLE)
      end
    end

    def visit_unless(node)
      visit(node.predicate)
      branchunless = builder.branchunless(-1)
      node.consequent ? visit(node.consequent) : builder.putnil

      if last_statement?
        builder.leave
        branchunless[1] = builder.label

        visit(node.statements)
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

    def visit_until(node)
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
      builder.branchunless(label)
      builder.putnil if last_statement?
    end

    def visit_var_field(node)
      case node.value
      when CVar, IVar
        name = node.value.value.to_sym
        current_iseq.inline_storage_for(name)
      when Ident
        name = node.value.value.to_sym

        if (local_variable = current_iseq.local_variable(name))
          local_variable
        else
          current_iseq.local_table.plain(name)
          current_iseq.local_variable(name)
        end
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
        when YARV::LocalTable::BlockLocal
          builder.getblockparam(lookup.index, lookup.level)
        when YARV::LocalTable::PlainLocal
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

      flag = YARV::VM_CALL_FCALL | YARV::VM_CALL_VCALL | YARV::VM_CALL_ARGS_SIMPLE
      builder.send(node.value.value.to_sym, 0, flag)
    end

    def visit_when(node)
      visit(node.statements)
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
        length = visit_string_parts(node)
        builder.concatstrings(length)
      end
    end

    def visit_words(node)
      if frozen_string_literal && (compiled = RubyVisitor.compile(node))
        builder.duparray(compiled)
      else
        visit_all(node.elements)
        builder.newarray(node.elements.length)
      end
    end

    def visit_xstring_literal(node)
      builder.putself
      length = visit_string_parts(node)
      builder.concatstrings(node.parts.length) if length > 1
      builder.send(:`, 1, YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE)
    end

    def visit_yield(node)
      parts = argument_parts(node.arguments)
      visit_all(parts)
      builder.invokeblock(nil, parts.length, YARV::VM_CALL_ARGS_SIMPLE)
    end

    def visit_zsuper(_node)
      builder.putself
      builder.invokesuper(
        nil,
        0,
        YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE | YARV::VM_CALL_SUPER | YARV::VM_CALL_ZSUPER,
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

        builder.dup
        builder.defined(YARV::DEFINED_CONST_FROM, name, true)
      when TopConstField
        name = node.target.constant.value.to_sym

        builder.putobject(Object)
        builder.dup
        builder.defined(YARV::DEFINED_CONST_FROM, name, true)
      when VarField
        name = node.target.value.value.to_sym
        builder.putnil

        case node.target.value
        when Const
          builder.defined(YARV::DEFINED_CONST, name, true)
        when CVar
          builder.defined(YARV::DEFINED_CVAR, name, true)
        when GVar
          builder.defined(YARV::DEFINED_GVAR, name, true)
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
          builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
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
      builder.objtostring(:to_s, 0, YARV::VM_CALL_FCALL | YARV::VM_CALL_ARGS_SIMPLE)
      builder.anytostring
    end

    # There are a lot of nodes in the AST that act as contains of parts of
    # strings. This includes things like string literals, regular expressions,
    # heredocs, etc. This method will visit all the parts of a string within
    # those containers.
    def visit_string_parts(node)
      length = 0

      unless node.parts.first.is_a?(TStringContent)
        builder.putobject("")
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
          builder.putobject(part.accept(RubyVisitor.new))
        end

        length += 1
      end

      length
    end

    # The current instruction sequence that we're compiling is always stored
    # on the compiler. When we descend into a node that has its own
    # instruction sequence, this method can be called to temporarily set the
    # new value of the instruction sequence, yield, and then set it back.
    def with_instruction_sequence(type, name, parent_iseq, node)
      previous_iseq = current_iseq
      previous_builder = builder

      begin
        iseq = YARV::InstructionSequence.new(type, name, parent_iseq, node.location)

        @current_iseq = iseq
        @builder =
          YARV::Builder.new(
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
        builder.putnil
        visit(node.target.collection)
        visit(node.target.index)

        builder.dupn(2)
        builder.send(:[], 1, YARV::VM_CALL_ARGS_SIMPLE)

        yield

        builder.setn(3)
        builder.send(:[]=, 2, YARV::VM_CALL_ARGS_SIMPLE)
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
          builder.putspecialobject(YARV::VM_SPECIAL_OBJECT_CONST_BASE)
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
