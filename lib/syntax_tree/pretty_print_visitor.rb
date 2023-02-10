# frozen_string_literal: true

module SyntaxTree
  # This visitor pretty-prints the AST into an equivalent s-expression.
  class PrettyPrintVisitor < FieldVisitor
    attr_reader :q

    def initialize(q)
      @q = q
    end

    # This is here because we need to make sure the operator is cast to a string
    # before we print it out.
    def visit_binary(node)
      node(node, "binary") do
        field("left", node.left)
        text("operator", node.operator.to_s)
        field("right", node.right)
        comments(node)
      end
    end

    # This is here to make it a little nicer to look at labels since they
    # typically have their : at the end of the value.
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
        q.seplist(node.comments) { |comment| q.pp(comment) }
      end
    end

    def field(_name, value)
      q.breakable
      q.pp(value)
    end

    def list(_name, values)
      q.breakable
      q.group(2, "(", ")") { q.seplist(values) { |value| q.pp(value) } }
    end

    def node(_node, type)
      q.group(2, "(", ")") do
        q.text(type)
        yield
      end
    end

    def pairs(_name, values)
      q.group(2, "(", ")") do
        q.seplist(values) do |(key, value)|
          q.pp(key)

          if value
            q.text("=")
            q.group(2) do
              q.breakable("")
              q.pp(value)
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
