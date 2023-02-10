# frozen_string_literal: true

require "cgi"

module SyntaxTree
  # This module is responsible for rendering mermaid flow charts.
  module Mermaid
    def self.escape(label)
      "\"#{CGI.escapeHTML(label)}\""
    end

    class Link
      TYPES = %i[directed].freeze
      COLORS = %i[green red].freeze

      attr_reader :from, :to, :label, :type, :color

      def initialize(from, to, label, type, color)
        raise if !TYPES.include?(type)
        raise if color && !COLORS.include?(color)

        @from = from
        @to = to
        @label = label
        @type = type
        @color = color
      end

      def render
        case type
        when :directed
          if label
            "#{from.id} -- #{Mermaid.escape(label)} --> #{to.id}"
          else
            "#{from.id} --> #{to.id}"
          end
        end
      end
    end

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
        "#{id}#{left_bound}#{Mermaid.escape(label)}#{right_bound}"
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

    class FlowChart
      attr_reader :output, :prefix, :nodes, :links

      def initialize
        @output = StringIO.new
        @output.puts("flowchart TD")
        @prefix = "  "

        @nodes = {}
        @links = []
      end

      def fetch(id)
        nodes.fetch(id)
      end

      def link(from, to, label = nil, type: :directed, color: nil)
        link = Link.new(from, to, label, type, color)
        links << link

        output.puts("#{prefix}#{link.render}")
        link
      end

      def node(id, label, shape: :rectangle)
        node = Node.new(id, label, shape)
        nodes[id] = node

        output.puts("#{prefix}#{nodes[id].render}")
        node
      end

      def subgraph(label)
        output.puts("#{prefix}subgraph #{Mermaid.escape(label)}")

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
        links.each_with_index do |link, index|
          if link.color
            output.puts("#{prefix}linkStyle #{index} stroke:#{link.color}")
          end
        end

        output.string
      end
    end
  end
end
