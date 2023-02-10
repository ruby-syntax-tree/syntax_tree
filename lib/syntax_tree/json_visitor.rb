# frozen_string_literal: true

require "json"

module SyntaxTree
  # This visitor transforms the AST into a hash that contains only primitives
  # that can be easily serialized into JSON.
  class JSONVisitor < FieldVisitor
    attr_reader :target

    def initialize
      @target = nil
    end

    private

    def comments(node)
      target[:comments] = visit_all(node.comments)
    end

    def field(name, value)
      target[name] = value.is_a?(Node) ? visit(value) : value
    end

    def list(name, values)
      target[name] = visit_all(values)
    end

    def node(node, type)
      previous = @target
      @target = { type: type, location: visit_location(node.location) }
      yield
      @target
    ensure
      @target = previous
    end

    def pairs(name, values)
      target[name] = values.map { |(key, value)| [visit(key), visit(value)] }
    end

    def text(name, value)
      target[name] = value
    end

    def visit_location(location)
      [
        location.start_line,
        location.start_char,
        location.end_line,
        location.end_char
      ]
    end
  end
end
