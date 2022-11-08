# frozen_string_literal: true

module SyntaxTree
  # A pattern is an object that wraps a Ruby pattern matching expression. The
  # expression would normally be passed to an `in` clause within a `case`
  # expression or a rightward assignment expression. For example, in the
  # following snippet:
  #
  #     case node
  #     in Const[value: "SyntaxTree"]
  #     end
  #
  # the pattern is the `Const[value: "SyntaxTree"]` expression. Within Syntax
  # Tree, every node generates these kinds of expressions using the
  # #construct_keys method.
  #
  # The pattern gets compiled into an object that responds to call by running
  # the #compile method. This method itself will run back through Syntax Tree to
  # parse the expression into a tree, then walk the tree to generate the
  # necessary callable objects. For example, if you wanted to compile the
  # expression above into a callable, you would:
  #
  #     callable = SyntaxTree::Pattern.new("Const[value: 'SyntaxTree']").compile
  #     callable.call(node)
  #
  # The callable object returned by #compile is guaranteed to respond to #call
  # with a single argument, which is the node to match against. It also is
  # guaranteed to respond to #===, which means it itself can be used in a `case`
  # expression, as in:
  #
  #     case node
  #     when callable
  #     end
  #
  # If the query given to the initializer cannot be compiled into a valid
  # matcher (either because of a syntax error or because it is using syntax we
  # do not yet support) then a SyntaxTree::Pattern::CompilationError will be
  # raised.
  class Pattern
    # Raised when the query given to a pattern is either invalid Ruby syntax or
    # is using syntax that we don't yet support.
    class CompilationError < StandardError
      def initialize(repr)
        super(<<~ERROR)
          Syntax Tree was unable to compile the pattern you provided to search
          into a usable expression. It failed on to understand the node
          represented by:

          #{repr}

          Note that not all syntax supported by Ruby's pattern matching syntax
          is also supported by Syntax Tree's code search. If you're using some
          syntax that you believe should be supported, please open an issue on
          GitHub at https://github.com/ruby-syntax-tree/syntax_tree/issues/new.
        ERROR
      end
    end

    attr_reader :query

    def initialize(query)
      @query = query
    end

    def compile
      program =
        begin
          SyntaxTree.parse("case nil\nin #{query}\nend")
        rescue Parser::ParseError
          raise CompilationError, query
        end

      compile_node(program.statements.body.first.consequent.pattern)
    end

    private

    # Shortcut for combining two procs into one that returns true if both return
    # true.
    def combine_and(left, right)
      ->(other) { left.call(other) && right.call(other) }
    end

    # Shortcut for combining two procs into one that returns true if either
    # returns true.
    def combine_or(left, right)
      ->(other) { left.call(other) || right.call(other) }
    end

    # Raise an error because the given node is not supported.
    def compile_error(node)
      raise CompilationError, PP.pp(node, +"").chomp
    end

    # There are a couple of nodes (string literals, dynamic symbols, and regexp)
    # that contain list of parts. This can include plain string content,
    # interpolated expressions, and interpolated variables. We only support
    # plain string content, so this method will extract out the plain string
    # content if it is the only element in the list.
    def extract_string(node)
      parts = node.parts

      if parts.length == 1 && (part = parts.first) && part.is_a?(TStringContent)
        part.value
      end
    end

    # in [foo, bar, baz]
    def compile_aryptn(node)
      compile_error(node) if !node.rest.nil? || node.posts.any?

      constant = node.constant
      compiled_constant = compile_node(constant) if constant

      preprocessed = node.requireds.map { |required| compile_node(required) }

      compiled_requireds = ->(other) do
        deconstructed = other.deconstruct

        deconstructed.length == preprocessed.length &&
          preprocessed
            .zip(deconstructed)
            .all? { |(matcher, value)| matcher.call(value) }
      end

      if compiled_constant
        combine_and(compiled_constant, compiled_requireds)
      else
        compiled_requireds
      end
    end

    # in foo | bar
    def compile_binary(node)
      compile_error(node) if node.operator != :|

      combine_or(compile_node(node.left), compile_node(node.right))
    end

    # in Ident
    # in String
    def compile_const(node)
      value = node.value

      if SyntaxTree.const_defined?(value, false)
        clazz = SyntaxTree.const_get(value)

        ->(other) { clazz === other }
      elsif Object.const_defined?(value, false)
        clazz = Object.const_get(value)

        ->(other) { clazz === other }
      else
        compile_error(node)
      end
    end

    # in SyntaxTree::Ident
    def compile_const_path_ref(node)
      parent = node.parent
      compile_error(node) if !parent.is_a?(VarRef) || !parent.value.is_a?(Const)

      if parent.value.value == "SyntaxTree"
        compile_node(node.constant)
      else
        compile_error(node)
      end
    end

    # in :""
    # in :"foo"
    def compile_dyna_symbol(node)
      if node.parts.empty?
        symbol = :""

        ->(other) { symbol === other }
      elsif (value = extract_string(node))
        symbol = value.to_sym

        ->(other) { symbol === other }
      else
        compile_error(node)
      end
    end

    # in Ident[value: String]
    # in { value: String }
    def compile_hshptn(node)
      compile_error(node) unless node.keyword_rest.nil?
      compiled_constant = compile_node(node.constant) if node.constant

      preprocessed =
        node.keywords.to_h do |keyword, value|
          compile_error(node) unless keyword.is_a?(Label)
          [keyword.value.chomp(":").to_sym, compile_node(value)]
        end

      compiled_keywords = ->(other) do
        deconstructed = other.deconstruct_keys(preprocessed.keys)

        preprocessed.all? do |keyword, matcher|
          matcher.call(deconstructed[keyword])
        end
      end

      if compiled_constant
        combine_and(compiled_constant, compiled_keywords)
      else
        compiled_keywords
      end
    end

    # in /foo/
    def compile_regexp_literal(node)
      if (value = extract_string(node))
        regexp = /#{value}/

        ->(attribute) { regexp === attribute }
      else
        compile_error(node)
      end
    end

    # in ""
    # in "foo"
    def compile_string_literal(node)
      if node.parts.empty?
        ->(attribute) { "" === attribute }
      elsif (value = extract_string(node))
        ->(attribute) { value === attribute }
      else
        compile_error(node)
      end
    end

    # in :+
    # in :foo
    def compile_symbol_literal(node)
      symbol = node.value.value.to_sym

      ->(attribute) { symbol === attribute }
    end

    # in Foo
    # in nil
    def compile_var_ref(node)
      value = node.value

      if value.is_a?(Const)
        compile_node(value)
      elsif value.is_a?(Kw) && value.value.nil?
        ->(attribute) { nil === attribute }
      else
        compile_error(node)
      end
    end

    # Compile any kind of node. Dispatch out to the individual compilation
    # methods based on the type of node.
    def compile_node(node)
      case node
      when AryPtn
        compile_aryptn(node)
      when Binary
        compile_binary(node)
      when Const
        compile_const(node)
      when ConstPathRef
        compile_const_path_ref(node)
      when DynaSymbol
        compile_dyna_symbol(node)
      when HshPtn
        compile_hshptn(node)
      when RegexpLiteral
        compile_regexp_literal(node)
      when StringLiteral
        compile_string_literal(node)
      when SymbolLiteral
        compile_symbol_literal(node)
      when VarRef
        compile_var_ref(node)
      else
        compile_error(node)
      end
    end
  end
end
