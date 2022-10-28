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

    def combine_and(left, right)
      ->(node) { left.call(node) && right.call(node) }
    end

    def combine_or(left, right)
      ->(node) { left.call(node) || right.call(node) }
    end

    def compile_node(root)
      if AryPtn === root and root.rest.nil? and root.posts.empty?
        constant = root.constant
        compiled_constant = compile_node(constant) if constant

        preprocessed = root.requireds.map { |required| compile_node(required) }

        compiled_requireds = ->(node) do
          deconstructed = node.deconstruct

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
      elsif Binary === root and root.operator == :|
        combine_or(compile_node(root.left), compile_node(root.right))
      elsif Const === root and SyntaxTree.const_defined?(root.value)
        clazz = SyntaxTree.const_get(root.value)

        ->(node) { node.is_a?(clazz) }
      elsif Const === root and Object.const_defined?(root.value)
        clazz = Object.const_get(root.value)

        ->(node) { node.is_a?(clazz) }
      elsif ConstPathRef === root and VarRef === root.parent and
            Const === root.parent.value and
            root.parent.value.value == "SyntaxTree"
        compile_node(root.constant)
      elsif DynaSymbol === root and root.parts.empty?
        symbol = :""

        ->(node) { node == symbol }
      elsif DynaSymbol === root and parts = root.parts and parts.size == 1 and
            TStringContent === parts[0]
        symbol = parts[0].value.to_sym

        ->(node) { node == symbol }
      elsif HshPtn === root and root.keyword_rest.nil?
        compiled_constant = compile_node(root.constant)

        preprocessed =
          root.keywords.to_h do |keyword, value|
            unless keyword.is_a?(Label)
              raise CompilationError, PP.pp(root, +"").chomp
            end
            [keyword.value.chomp(":").to_sym, compile_node(value)]
          end

        compiled_keywords = ->(node) do
          deconstructed = node.deconstruct_keys(preprocessed.keys)

          preprocessed.all? do |keyword, matcher|
            matcher.call(deconstructed[keyword])
          end
        end

        if compiled_constant
          combine_and(compiled_constant, compiled_keywords)
        else
          compiled_keywords
        end
      elsif RegexpLiteral === root and parts = root.parts and
            parts.size == 1 and TStringContent === parts[0]
        regexp = /#{parts[0].value}/

        ->(attribute) { regexp.match?(attribute) }
      elsif StringLiteral === root and root.parts.empty?
        ->(attribute) { attribute == "" }
      elsif StringLiteral === root and parts = root.parts and
            parts.size == 1 and TStringContent === parts[0]
        value = parts[0].value
        ->(attribute) { attribute == value }
      elsif SymbolLiteral === root
        symbol = root.value.value.to_sym

        ->(attribute) { attribute == symbol }
      elsif VarRef === root and Const === root.value
        compile_node(root.value)
      elsif VarRef === root and Kw === root.value and root.value.value.nil?
        ->(attribute) { attribute.nil? }
      else
        raise CompilationError, PP.pp(root, +"").chomp
      end
    end
  end
end
