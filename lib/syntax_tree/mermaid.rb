# frozen_string_literal: true

require "cgi"

module SyntaxTree
  # This module is responsible for rendering mermaid flow charts.
  module Mermaid
    class Node
      SHAPES = %i[circle rectangle stadium].freeze

      attr_reader :id, :label, :shape

      def initialize(id, label, shape)
        raise unless SHAPES.include?(shape)

        @id = id
        @label = label
        @shape = shape
      end

      def render
        left_bound, right_bound =
          case shape
          when :circle
            ["((", "))"]
          when :rectangle
            ["[", "]"]
          when :stadium
            ["([", "])"]
          end

        "  #{id}#{left_bound}\"#{CGI.escapeHTML(label)}\"#{right_bound}"
      end
    end

    class Edge
      TYPES = %i[directed].freeze

      attr_reader :from, :to, :label, :type

      def initialize(from, to, label, type)
        raise unless TYPES.include?(type)

        @from = from
        @to = to
        @label = label
        @type = type
      end

      def render
        case type
        when :directed
          "  #{from.id} -- \"#{CGI.escapeHTML(label)}\" --> #{to.id}"
        end
      end
    end

    class FlowChart
      attr_reader :nodes, :edges

      def initialize
        @nodes = {}
        @edges = []
      end

      def edge(from, to, label, type = :directed)
        edges << Edge.new(from, to, label, type)
      end

      def node(id, label, shape = :rectangle)
        nodes[id] = Node.new(id, label, shape)
      end

      def render
        output = StringIO.new
        output.puts("flowchart TD")

        nodes.each_value { |node| output.puts(node.render) }
        edges.each { |edge| output.puts(edge.render) }

        output.string
      end
    end
  end
end
