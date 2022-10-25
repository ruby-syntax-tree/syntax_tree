# frozen_string_literal: true

module SyntaxTree
  # Provides an interface for searching for a pattern of nodes against a
  # subtree of an AST.
  class Search
    attr_reader :pattern

    def initialize(pattern)
      @pattern = pattern
    end

    def scan(root)
      return to_enum(__method__, root) unless block_given?
      queue = [root]

      until queue.empty?
        node = queue.shift
        next unless node

        yield node if pattern.call(node)
        queue += node.child_nodes
      end
    end
  end
end
