# frozen_string_literal: true

module SyntaxTree
  # This visitor transforms the AST into a Ruby pattern matching expression that
  # would match correctly against the AST.
  class MatchVisitor < FieldVisitor
    attr_reader :q

    def initialize(q)
      @q = q
    end

    def visit(node)
      case node
      when Node
        super
      when String
        # pp will split up a string on newlines and concat them together using a
        # "+" operator. This breaks the pattern matching expression. So instead
        # we're going to check here for strings and manually put the entire
        # value into the output buffer.
        q.text(node.inspect)
      else
        node.pretty_print(q)
      end
    end

    private

    def comments(node)
      return if node.comments.empty?

      q.nest(0) do
        q.text("comments: [")
        q.indent do
          q.breakable("")
          q.seplist(node.comments) { |comment| visit(comment) }
        end
        q.breakable("")
        q.text("]")
      end
    end

    def field(name, value)
      q.nest(0) do
        q.text(name)
        q.text(": ")
        visit(value)
      end
    end

    def list(name, values)
      q.group do
        q.text(name)
        q.text(": [")
        q.indent do
          q.breakable("")
          q.seplist(values) { |value| visit(value) }
        end
        q.breakable("")
        q.text("]")
      end
    end

    def node(node, _type)
      items = []
      q.with_target(items) { yield }

      if items.empty?
        q.text(node.class.name)
        return
      end

      q.group do
        q.text(node.class.name)
        q.text("[")
        q.indent do
          q.breakable("")
          q.seplist(items) { |item| q.target << item }
        end
        q.breakable("")
        q.text("]")
      end
    end

    def pairs(name, values)
      q.group do
        q.text(name)
        q.text(": [")
        q.indent do
          q.breakable("")
          q.seplist(values) do |(key, value)|
            q.group do
              q.text("[")
              q.indent do
                q.breakable("")
                visit(key)
                q.text(",")
                q.breakable
                visit(value || nil)
              end
              q.breakable("")
              q.text("]")
            end
          end
        end
        q.breakable("")
        q.text("]")
      end
    end

    def text(name, value)
      q.nest(0) do
        q.text(name)
        q.text(": ")
        value.pretty_print(q)
      end
    end
  end
end
