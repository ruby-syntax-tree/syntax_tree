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

    def compile(pattern)
      case pattern
      in Binary[left:, operator: :|, right:]
        compiled_left = compile(left)
        compiled_right = compile(right)

        ->(node) { compiled_left.call(node) || compiled_right.call(node) }
      in Const[value:] if SyntaxTree.const_defined?(value)
        clazz = SyntaxTree.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in Const[value:] if Object.const_defined?(value)
        clazz = Object.const_get(value)

        ->(node) { node.is_a?(clazz) }
      in ConstPathRef[parent: VarRef[value: Const[value: "SyntaxTree"]]]
        compile(pattern.constant)
      in HshPtn[constant:, keywords:, keyword_rest: nil]
        compiled_constant = compile(constant)

        preprocessed_keywords =
          keywords.to_h do |keyword, value|
            raise NoMatchingPatternError unless keyword.is_a?(Label)
            [keyword.value.chomp(":").to_sym, compile(value)]
          end

        compiled_keywords = ->(node) do
          deconstructed = node.deconstruct_keys(preprocessed_keywords.keys)
          preprocessed_keywords.all? do |keyword, matcher|
            matcher.call(deconstructed[keyword])
          end
        end

        ->(node) do
          compiled_constant.call(node) && compiled_keywords.call(node)
        end
      in RegexpLiteral[parts: [TStringContent[value:]]]
        regexp = /#{value}/

        ->(attribute) { regexp.match?(attribute) }
      in StringLiteral[parts: [TStringContent[value:]]]
        ->(attribute) { attribute == value }
      in VarRef[value: Const => value]
        compile(value)
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
