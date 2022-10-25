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
      case root
      in AryPtn[constant:, requireds:, rest: nil, posts: []]
        compiled_constant = compile_node(constant) if constant

        preprocessed = requireds.map { |required| compile_node(required) }

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
      in Binary[left:, operator: :|, right:]
        combine_or(compile_node(left), compile_node(right))
      in Const[value:] if SyntaxTree.const_defined?(value)
        clazz = SyntaxTree.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in Const[value:] if Object.const_defined?(value)
        clazz = Object.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in ConstPathRef[
           parent: VarRef[value: Const[value: "SyntaxTree"]], constant:
         ]
        compile_node(constant)
      in DynaSymbol[parts: []]
        symbol = :""

        ->(node) { node == symbol }
      in DynaSymbol[parts: [TStringContent[value:]]]
        symbol = value.to_sym

        ->(attribute) { attribute == value }
      in HshPtn[constant:, keywords:, keyword_rest: nil]
        compiled_constant = compile_node(constant)

        preprocessed =
          keywords.to_h do |keyword, value|
            raise NoMatchingPatternError unless keyword.is_a?(Label)
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
      in RegexpLiteral[parts: [TStringContent[value:]]]
        regexp = /#{value}/

        ->(attribute) { regexp.match?(attribute) }
      in StringLiteral[parts: []]
        ->(attribute) { attribute == "" }
      in StringLiteral[parts: [TStringContent[value:]]]
        ->(attribute) { attribute == value }
      in SymbolLiteral[value:]
        symbol = value.value.to_sym

        ->(attribute) { attribute == symbol }
      in VarRef[value: Const => value]
        compile_node(value)
      in VarRef[value: Kw[value: "nil"]]
        ->(attribute) { attribute.nil? }
      end
    rescue NoMatchingPatternError
      raise CompilationError, PP.pp(root, +"").chomp
    end
  end
end
