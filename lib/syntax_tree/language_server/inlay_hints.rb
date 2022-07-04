# frozen_string_literal: true

module SyntaxTree
  class LanguageServer
    # This class provides inlay hints for the language server. It existed
    # before the spec was finalized so, so it provides two result formats:
    # aligned with the spec (`#all`) and proprietary (`#before` and `#after`).
    #
    # For more information, see the spec here:
    # https://github.com/microsoft/language-server-protocol/issues/956.
    #
    class InlayHints < Visitor
      attr_reader :stack, :all, :before, :after

      def initialize
        @stack = []
        @all = []
        @before = Hash.new { |hash, key| hash[key] = +"" }
        @after = Hash.new { |hash, key| hash[key] = +"" }
      end

      def visit(node)
        stack << node
        result = super
        stack.pop
        result
      end

      # Adds parentheses around assignments contained within the default values
      # of parameters. For example,
      #
      #     def foo(a = b = c)
      #     end
      #
      # becomes
      #
      #     def foo(a = ₍b = c₎)
      #     end
      #
      def visit_assign(node)
        parentheses(node.location) if stack[-2].is_a?(Params)
        super
      end

      # Adds parentheses around binary expressions to make it clear which
      # subexpression will be evaluated first. For example,
      #
      #     a + b * c
      #
      # becomes
      #
      #     a + ₍b * c₎
      #
      def visit_binary(node)
        case stack[-2]
        in Assign | OpAssign
          parentheses(node.location)
        in Binary[operator: operator] if operator != node.operator
          parentheses(node.location)
        else
        end

        super
      end

      # Adds parentheses around ternary operators contained within certain
      # expressions where it could be confusing which subexpression will get
      # evaluated first. For example,
      #
      #     a ? b : c ? d : e
      #
      # becomes
      #
      #     a ? b : ₍c ? d : e₎
      #
      def visit_if_op(node)
        case stack[-2]
        in Assign | Binary | IfOp | OpAssign
          parentheses(node.location)
        else
        end

        super
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
      def visit_rescue(node)
        if node.exception.nil?
          after[node.location.start_char + "rescue".length] << " StandardError"
          all << {
            position: {
              line: node.location.start_line - 1,
              character: node.location.start_column + "rescue".length
            },
            label: " StandardError"
          }
        end

        super
      end

      # Adds parentheses around unary statements using the - operator that are
      # contained within Binary nodes. For example,
      #
      #     -a + b
      #
      # becomes
      #
      #     ₍-a₎ + b
      #
      def visit_unary(node)
        if stack[-2].is_a?(Binary) && (node.operator == "-")
          parentheses(node.location)
        end

        super
      end

      def self.find(program)
        visitor = new
        visitor.visit(program)
        visitor
      end

      private

      def parentheses(location)
        all << {
          position: {
            line: location.start_line - 1,
            character: location.start_column
          },
          label: "₍"
        }
        all << {
          position: {
            line: location.end_line - 1,
            character: location.end_column
          },
          label: "₎"
        }
        before[location.start_char] << "₍"
        after[location.end_char] << "₎"
      end
    end
  end
end
