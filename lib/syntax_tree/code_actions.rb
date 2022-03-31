# frozen_string_literal: true

module SyntaxTree
  class CodeActions
    class DisasmAction
      attr_reader :line, :node

      def initialize(line, node)
        @line = line
        @node = node
      end

      def as_json
        {
          title: "Disasm #{node.name.value}",
          command: "syntaxTree.disasm",
          arguments: [line, node.name.value]
        }
      end
    end

    attr_reader :line, :actions

    def initialize(line)
      @line = line
      @actions = []
    end

    def disasm(node)
      @actions << DisasmAction.new(line, node)
    end

    def self.find(program, line)
      code_actions = new(line)
      queue = [program]

      until queue.empty?
        node = queue.shift

        # If we're found a method definition that starts on the given line, then
        # we're going to add the disasm code action for that node.
        if [Def, DefEndless, Defs].include?(node.class) && node.location.start_line == line
          code_actions.disasm(node)
        end

        # Check if the node covers the given line. If it doesn't, then we just
        # bail out and go to the next node in the queue.
        next unless node.location.lines.cover?(line)

        # Get a list of child nodes and binary search over them to find the
        # first child node that covers the given line. It's possible that there
        # are multiple, but at least we'll have a handle on one of them.
        child_nodes = node.child_nodes.compact
        index =
          child_nodes.bsearch_index do |child|
            if child.location.lines.cover?(line)
              0
            else
              line - child.location.start_line
            end
          end

        # If no valid child was found, then just continue on to the next node in
        # the queue.
        next unless index

        # First, we're going to go backward in our list until we find the start
        # of the subset of child nodes that cover the given line. We're going to
        # add each one to the queue.
        current = index - 1
        while current > 0 && child_nodes[current].location.lines.cover?(line)
          queue << child_nodes[current]
          current -= 1
        end

        # Next, we're going to go forward in our list until we find the end of
        # the subset of child nodes that cover the given line. We'll add each of
        # those to the queue as well.
        current = index
        while current < child_nodes.length && child_nodes[current].location.lines.cover?(line)
          queue << child_nodes[current]
          current += 1
        end
      end

      code_actions
    end
  end
end
