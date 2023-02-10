# frozen_string_literal: true

require "cgi"
require "stringio"

module SyntaxTree
  # This module is responsible for rendering mermaid (https://mermaid.js.org/)
  # flow charts.
  module Mermaid
    # This is the main class that handles rendering a flowchart. It keeps track
    # of its nodes and links and renders them according to the mermaid syntax.
    class FlowChart
      attr_reader :output, :prefix, :nodes, :links

      def initialize
        @output = StringIO.new
        @output.puts("flowchart TD")
        @prefix = "  "

        @nodes = {}
        @links = []
      end

      # Retrieve a node that has already been added to the flowchart by its id.
      def fetch(id)
        nodes.fetch(id)
      end

      # Add a link to the flowchart between two nodes with an optional label.
      def link(from, to, label = nil, type: :directed, color: nil)
        link = Link.new(from, to, label, type, color)
        links << link

        output.puts("#{prefix}#{link.render}")
        link
      end

      # Add a node to the flowchart with an optional label.
      def node(id, label = " ", shape: :rectangle)
        node = Node.new(id, label, shape)
        nodes[id] = node

        output.puts("#{prefix}#{nodes[id].render}")
        node
      end

      # Add a subgraph to the flowchart. Within the given block, all of the
      # nodes will be rendered within the subgraph.
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

      # Return the rendered flowchart.
      def render
        links.each_with_index do |link, index|
          if link.color
            output.puts("#{prefix}linkStyle #{index} stroke:#{link.color}")
          end
        end

        output.string
      end
    end

    # This class represents a link between two nodes in a flowchart. It is not
    # meant to be interacted with directly, but rather used as a data structure
    # by the FlowChart class.
    class Link
      TYPES = %i[directed dotted].freeze
      COLORS = %i[green red].freeze

      attr_reader :from, :to, :label, :type, :color

      def initialize(from, to, label, type, color)
        raise unless TYPES.include?(type)
        raise if color && !COLORS.include?(color)

        @from = from
        @to = to
        @label = label
        @type = type
        @color = color
      end

      def render
        left_side, right_side, full_side = sides

        if label
          escaped = Mermaid.escape(label)
          "#{from.id} #{left_side} #{escaped} #{right_side} #{to.id}"
        else
          "#{from.id} #{full_side} #{to.id}"
        end
      end

      private

      def sides
        case type
        when :directed
          %w[-- --> -->]
        when :dotted
          %w[-. .-> -.->]
        end
      end
    end

    # This class represents a node in a flowchart. Unlike the Link class, it can
    # be used directly. It is the return value of the #node method, and is meant
    # to be passed around to #link methods to create links between nodes.
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
          %w[(( ))]
        when :rectangle
          ["[", "]"]
        when :rounded
          %w[( )]
        when :stadium
          ["([", "])"]
        end
      end
    end

    class << self
      # Escape a label to be used in the mermaid syntax. This is used to escape
      # HTML entities such that they render properly within the quotes.
      def escape(label)
        "\"#{CGI.escapeHTML(label)}\""
      end

      # Create a new flowchart. If a block is given, it will be yielded to and
      # the flowchart will be rendered. Otherwise, the flowchart will be
      # returned.
      def flowchart
        flowchart = FlowChart.new

        if block_given?
          yield flowchart
          flowchart.render
        else
          flowchart
        end
      end
    end
  end
end
