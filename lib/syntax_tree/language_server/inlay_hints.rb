# frozen_string_literal: true

module SyntaxTree
  class LanguageServer
    class InlayHints
      attr_reader :before, :after

      def initialize
        @before = Hash.new { |hash, key| hash[key] = +"" }
        @after = Hash.new { |hash, key| hash[key] = +"" }
      end

      # Adds the implicitly rescued StandardError into a bare rescue clause. For
      # example,
      #
      #     begin
      #     rescue
      #     end
      #
      # becomes
      #
      #     begin
      #     rescue StandardError
      #     end
      #
      def bare_rescue(location)
        after[location.start_char + "rescue".length] << " StandardError"
      end

      # Adds implicit parentheses around certain expressions to make it clear
      # which subexpression will be evaluated first. For example,
      #
      #     a + b * c
      #
      # becomes
      #
      #     a + ₍b * c₎
      #
      def precedence_parentheses(location)
        before[location.start_char] << "₍"
        after[location.end_char] << "₎"
      end

      def self.find(program)
        inlay_hints = new
        queue = [[nil, program]]

        until queue.empty?
          parent_node, child_node = queue.shift

          child_node.child_nodes.each do |grand_child_node|
            queue << [child_node, grand_child_node] if grand_child_node
          end

          case [parent_node, child_node]
          in _, Rescue[exception: nil, location:]
            inlay_hints.bare_rescue(location)
          in Assign | Binary | IfOp | OpAssign, IfOp[location:]
            inlay_hints.precedence_parentheses(location)
          in Assign | OpAssign, Binary[location:]
            inlay_hints.precedence_parentheses(location)
          in Binary[operator: parent_oper], Binary[operator: child_oper, location:] if parent_oper != child_oper
            inlay_hints.precedence_parentheses(location)
          in Binary, Unary[operator: "-", location:]
            inlay_hints.precedence_parentheses(location)
          in Params, Assign[location:]
            inlay_hints.precedence_parentheses(location)
          else
            # do nothing
          end
        end

        inlay_hints
      end
    end
  end
end
