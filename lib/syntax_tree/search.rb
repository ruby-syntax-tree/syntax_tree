# frozen_string_literal: true

module SyntaxTree
  # Provides an interface for searching for a pattern of nodes against a
  # subtree of an AST.
  class Search
    class UncompilableError < StandardError
    end

    attr_reader :matcher

    def initialize(query)
      root = SyntaxTree.parse("case nil\nin #{query}\nend")
      @matcher = compile(root.statements.body.first.consequent.pattern)
    end

    def scan(root)
      return to_enum(__method__, root) unless block_given?
      queue = [root]

      until queue.empty?
        node = queue.shift
        next unless node

        yield node if matcher.call(node)
        queue += node.child_nodes
      end
    end

    private

    def combine_and(left, right)
      ->(node) { left.call(node) && right.call(node) }
    end

    def combine_or(left, right)
      ->(node) { left.call(node) || right.call(node) }
    end

    def compile(pattern)
      case pattern
      in AryPtn[constant:, requireds:, rest: nil, posts: []]
        compiled_constant = compile(constant) if constant

        preprocessed = requireds.map { |required| compile(required) }

        compiled_requireds = ->(node) do
          deconstructed = node.deconstruct

          deconstructed.length == preprocessed.length &&
            preprocessed.zip(deconstructed).all? do |(matcher, value)|
              matcher.call(value)
            end
        end

        if compiled_constant
          combine_and(compiled_constant, compiled_requireds)
        else
          compiled_requireds
        end
      in Binary[left:, operator: :|, right:]
        combine_or(compile(left), compile_right)
      in Const[value:] if SyntaxTree.const_defined?(value)
        clazz = SyntaxTree.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in Const[value:] if Object.const_defined?(value)
        clazz = Object.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in ConstPathRef[parent: VarRef[value: Const[value: "SyntaxTree"]]]
        compile(pattern.constant)
      in DynaSymbol[parts: [TStringContent[value:]]]
        symbol = value.to_sym

        ->(attribute) { attribute == value }
      in HshPtn[constant:, keywords:, keyword_rest: nil]
        compiled_constant = compile(constant)

        preprocessed =
          keywords.to_h do |keyword, value|
            raise NoMatchingPatternError unless keyword.is_a?(Label)
            [keyword.value.chomp(":").to_sym, compile(value)]
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
        compile(value)
      in VarRef[value: Kw[value: "nil"]]
        ->(attribute) { attribute.nil? }
      end
    rescue NoMatchingPatternError
      raise UncompilableError, <<~ERROR
        Syntax Tree was unable to compile the pattern you provided to search
        into a usable expression. It failed on the node within the pattern
        matching expression represented by:

        #{PP.pp(pattern, +"").chomp}

        Note that not all syntax supported by Ruby's pattern matching syntax is
        also supported by Syntax Tree's code search. If you're using some syntax
        that you believe should be supported, please open an issue on the GitHub
        repository at https://github.com/ruby-syntax-tree/syntax_tree.
      ERROR
    end
  end
end
