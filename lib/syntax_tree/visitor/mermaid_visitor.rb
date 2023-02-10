# frozen_string_literal: true

module SyntaxTree
  class Visitor
    # This visitor transforms the AST into a mermaid flow chart.
    class MermaidVisitor < FieldVisitor
      attr_reader :flowchart, :target

      def initialize
        @flowchart = Mermaid::FlowChart.new
        @target = nil
      end

      def visit_program(node)
        super
        flowchart.render
      end

      private

      def comments(node)
        # Ignore
      end

      def field(name, value)
        case value
        when nil
          # skip
        when Node
          flowchart.edge(target, visit(value), name)
        else
          to = flowchart.node("#{target.id}_#{name}", value.inspect, shape: :stadium)
          flowchart.edge(target, to, name)
        end
      end

      def list(name, values)
        values.each_with_index do |value, index|
          field("#{name}[#{index}]", value)
        end
      end

      def node(node, type)
        previous_target = target

        begin
          @target = flowchart.node("node_#{node.object_id}", type)
          yield
          @target
        ensure
          @target = previous_target
        end
      end

      def pairs(name, values)
        values.each_with_index do |(key, value), index|
          to = flowchart.node("#{target.id}_#{name}_#{index}", " ", shape: :circle)

          flowchart.edge(target, to, "#{name}[#{index}]")
          flowchart.edge(to, visit(key), "[0]")
          flowchart.edge(to, visit(value), "[1]") if value
        end
      end

      def text(name, value)
        field(name, value)
      end
    end
  end
end
