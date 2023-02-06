# frozen_string_literal: true

module SyntaxTree
  class Visitor
    # This visitor transforms the AST into a mermaid flow chart.
    class MermaidVisitor < FieldVisitor
      attr_reader :output, :target

      def initialize
        @output = StringIO.new
        @output.puts("flowchart TD")

        @target = nil
      end

      def visit_program(node)
        super
        output.string
      end

      private

      def comments(node)
        # Ignore
      end

      def field(name, value)
        case value
        when Node
          node_id = visit(value)
          output.puts("  #{target} -- \"#{name}\" --> #{node_id}")
        when String
          node_id = "#{target}_#{name}"
          output.puts("  #{node_id}([#{CGI.escapeHTML(value.inspect)}])")
          output.puts("  #{target} -- \"#{name}\" --> #{node_id}")
        when nil
          # skip
        else
          node_id = "#{target}_#{name}"
          output.puts("  #{node_id}([\"#{CGI.escapeHTML(value.inspect)}\"])")
          output.puts("  #{target} -- \"#{name}\" --> #{node_id}")
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
          @target = "node_#{node.object_id}"

          yield

          output.puts("  #{@target}[\"#{type}\"]")
          @target
        ensure
          @target = previous_target
        end
      end

      def pairs(name, values)
        values.each_with_index do |(key, value), index|
          node_id = "#{target}_#{name}_#{index}"
          output.puts("  #{node_id}((\"&nbsp;\"))")
          output.puts("  #{target} -- \"#{name}[#{index}]\" --> #{node_id}")
          output.puts("  #{node_id} -- \"[0]\" --> #{visit(key)}")
          output.puts("  #{node_id} -- \"[1]\" --> #{visit(value)}") if value
        end
      end

      def text(name, value)
        field(name, value)
      end
    end
  end
end
