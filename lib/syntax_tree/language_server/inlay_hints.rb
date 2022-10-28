# frozen_string_literal: true

module SyntaxTree
  class LanguageServer
    # This class provides inlay hints for the language server. For more
    # information, see the spec here:
    # https://github.com/microsoft/language-server-protocol/issues/956.
    class InlayHints < Visitor
      # This represents a hint that is going to be displayed in the editor.
      class Hint
        attr_reader :line, :character, :label

        def initialize(line:, character:, label:)
          @line = line
          @character = character
          @label = label
        end

        # This is the shape that the LSP expects.
        def to_json(*opts)
          {
            position: {
              line: line,
              character: character
            },
            label: label
          }.to_json(*opts)
        end
      end

      attr_reader :stack, :hints

      def initialize
        @stack = []
        @hints = []
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
        when Assign, OpAssign
          parentheses(node.location)
        when Binary
          parentheses(node.location) if stack[-2].operator != node.operator
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
        when Assign, Binary, IfOp, OpAssign
          parentheses(node.location)
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
          hints << Hint.new(
            line: node.location.start_line - 1,
            character: node.location.start_column + "rescue".length,
            label: " StandardError"
          )
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

      private

      def parentheses(location)
        hints << Hint.new(
          line: location.start_line - 1,
          character: location.start_column,
          label: "₍"
        )

        hints << Hint.new(
          line: location.end_line - 1,
          character: location.end_column,
          label: "₎"
        )
      end
    end
  end
end
