# frozen_string_literal: true

require "cgi"

module SyntaxTree
  # This module is responsible for rendering mermaid flow charts.
  module Mermaid
    class Node
      SHAPES = %i[circle rectangle rounded stadium].freeze

      attr_reader :id, :label, :shape

      def initialize(id, label, shape)
        raise unless SHAPES.include?(shape)

        @id = id
        @label = label
        @shape = shape
      end

      def render
        left_bound, right_bound = bounds
        "#{id}#{left_bound}\"#{CGI.escapeHTML(label)}\"#{right_bound}"
      end

      private

      def bounds
        case shape
        when :circle
          ["((", "))"]
        when :rectangle
          ["[", "]"]
        when :rounded
          ["(", ")"]
        when :stadium
          ["([", "])"]
        end
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
          if label
            "#{from.id} -- \"#{CGI.escapeHTML(label)}\" --> #{to.id}"
          else
            "#{from.id} --> #{to.id}"
          end
        end
      end
    end

    class FlowChart
      attr_reader :output, :prefix, :nodes

      def initialize
        @output = StringIO.new
        @output.puts("flowchart TD")
        @prefix = "  "
        @nodes = {}
      end

      def edge(from, to, label = nil, type: :directed)
        edge = Edge.new(from, to, label, type)
        output.puts("#{prefix}#{edge.render}")
      end

      def fetch(id)
        nodes.fetch(id)
      end

      def node(id, label, shape: :rectangle)
        node = Node.new(id, label, shape)
        nodes[id] = node

        output.puts("#{prefix}#{nodes[id].render}")
        node
      end

      def subgraph(id)
        output.puts("#{prefix}subgraph #{id}")

        previous = prefix
        @prefix = "#{prefix}  "

        begin
          yield
        ensure
          @prefix = previous
          output.puts("#{prefix}end")
        end
      end

      def render
        output.string
      end
    end
  end
end
