# frozen_string_literal: true

module SyntaxTree
  class Visitor
    # This visitor pretty-prints the AST into an equivalent s-expression.
    class PrettyPrintVisitor < FieldVisitor
      attr_reader :q

      def initialize(q)
        @q = q
      end

      def visit_label(node)
        node(node, "label") do
          q.breakable
          q.text(":")
          q.text(node.value[0...-1])
          comments(node)
        end
      end

      private

      def comments(node)
        return if node.comments.empty?

        q.breakable
        q.group(2, "(", ")") do
          q.seplist(node.comments) { |comment| comment.pretty_print(q) }
        end
      end

      def field(_name, value)
        q.breakable

        # I don't entirely know why this is necessary, but in Ruby 2.7 there is
        # an issue with calling q.pp on strings that somehow involves inspect
        # keys. I'm purposefully avoiding the inspect key stuff here because I
        # know the tree does not contain any cycles.
        value.is_a?(String) ? q.text(value.inspect) : value.pretty_print(q)
      end

      def list(_name, values)
        q.breakable
        q.group(2, "(", ")") do
          q.seplist(values) { |value| value.pretty_print(q) }
        end
      end

      def node(node, type)
        q.group(2, "(", ")") do
          q.text(type)
          yield
        end
      end

      def pairs(_name, values)
        q.group(2, "(", ")") do
          q.seplist(values) do |(key, value)|
            key.pretty_print(q)

            if value
              q.text("=")
              q.group(2) do
                q.breakable("")
                value.pretty_print(q)
              end
            end
          end
        end
      end

      def text(_name, value)
        q.breakable
        q.text(value)
      end
    end
  end
end
