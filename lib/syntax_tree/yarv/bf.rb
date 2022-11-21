# frozen_string_literal: true

module SyntaxTree
  module YARV
    # Parses the given source code into a syntax tree, compiles that syntax tree
    # into YARV bytecode.
    class Bf
      class Node
        def format(q)
          Format.new(q).visit(self)
        end

        def pretty_print(q)
          PrettyPrint.new(q).visit(self)
        end
      end

      # The root node of the syntax tree.
      class Root < Node
        attr_reader :nodes, :location

        def initialize(nodes:, location:)
          @nodes = nodes
          @location = location
        end

        def accept(visitor)
          visitor.visit_root(self)
        end

        def child_nodes
          nodes
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { nodes: nodes, location: location }
        end
      end

      # [ ... ]
      class Loop < Node
        attr_reader :nodes, :location

        def initialize(nodes:, location:)
          @nodes = nodes
          @location = location
        end

        def accept(visitor)
          visitor.visit_loop(self)
        end

        def child_nodes
          nodes
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { nodes: nodes, location: location }
        end
      end

      # +
      class Increment < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_increment(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: "+", location: location }
        end
      end

      # -
      class Decrement < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_decrement(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: "-", location: location }
        end
      end

      # >
      class ShiftRight < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_shift_right(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: ">", location: location }
        end
      end

      # <
      class ShiftLeft < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_shift_left(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: "<", location: location }
        end
      end

      # ,
      class Input < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_input(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: ",", location: location }
        end
      end

      # .
      class Output < Node
        attr_reader :location

        def initialize(location:)
          @location = location
        end

        def accept(visitor)
          visitor.visit_output(self)
        end

        def child_nodes
          []
        end

        alias deconstruct child_nodes

        def deconstruct_keys(keys)
          { value: ".", location: location }
        end
      end

      # Allows visiting the syntax tree recursively.
      class Visitor
        def visit(node)
          node.accept(self)
        end
  
        def visit_all(nodes)
          nodes.map { |node| visit(node) }
        end
  
        def visit_child_nodes(node)
          visit_all(node.child_nodes)
        end
  
        # Visit a Root node.
        alias visit_root visit_child_nodes
  
        # Visit a Loop node.
        alias visit_loop visit_child_nodes
  
        # Visit an Increment node.
        alias visit_increment visit_child_nodes
  
        # Visit a Decrement node.
        alias visit_decrement visit_child_nodes
  
        # Visit a ShiftRight node.
        alias visit_shift_right visit_child_nodes
  
        # Visit a ShiftLeft node.
        alias visit_shift_left visit_child_nodes
  
        # Visit an Input node.
        alias visit_input visit_child_nodes
  
        # Visit an Output node.
        alias visit_output visit_child_nodes
      end

      # Compiles the syntax tree into YARV bytecode.
      class Compiler < Visitor
        attr_reader :iseq

        def initialize
          @iseq = InstructionSequence.new(:top, "<compiled>", nil, Location.default)
        end

        def visit_decrement(node)
          change_by(-1)
        end

        def visit_increment(node)
          change_by(1)
        end

        def visit_input(node)
          iseq.getglobal(:$tape)
          iseq.getglobal(:$cursor)
          iseq.getglobal(:$stdin)
          iseq.send(:getc, 0)
          iseq.send(:ord, 0)
          iseq.send(:[]=, 2)
        end

        def visit_loop(node)
          start_label = iseq.label

          # First, we're going to compare the value at the current cursor to 0.
          # If it's 0, then we'll jump past the loop. Otherwise we'll execute
          # the loop.
          iseq.getglobal(:$tape)
          iseq.getglobal(:$cursor)
          iseq.send(:[], 1)
          iseq.putobject(0)
          iseq.send(:==, 1)
          branchunless = iseq.branchunless(-1)

          # Otherwise, here we'll execute the loop.
          visit_nodes(node.nodes)

          # Now that we've visited all of the child nodes, we need to jump back
          # to the start of the loop.
          iseq.jump(start_label)

          # Now that we have all of the instructions in place, we can patch the
          # branchunless to point to the next instruction for skipping the loop.
          branchunless[1] = iseq.label
        end

        def visit_output(node)
          iseq.getglobal(:$stdout)
          iseq.getglobal(:$tape)
          iseq.getglobal(:$cursor)
          iseq.send(:[], 1)
          iseq.send(:chr, 0)
          iseq.send(:putc, 1)
        end

        def visit_root(node)
          iseq.duphash({ 0 => 0 })
          iseq.setglobal(:$tape)
          iseq.getglobal(:$tape)
          iseq.putobject(0)
          iseq.send(:default=, 1)

          iseq.putobject(0)
          iseq.setglobal(:$cursor)

          visit_nodes(node.nodes)

          iseq.leave
          iseq
        end

        def visit_shift_left(node)
          shift_by(-1)
        end

        def visit_shift_right(node)
          shift_by(1)
        end

        private

        def change_by(value)
          iseq.getglobal(:$tape)
          iseq.getglobal(:$cursor)
          iseq.getglobal(:$tape)
          iseq.getglobal(:$cursor)
          iseq.send(:[], 1)

          if value < 0
            iseq.putobject(-value)
            iseq.send(:-, 1)
          else
            iseq.putobject(value)
            iseq.send(:+, 1)
          end

          iseq.send(:[]=, 2)
        end

        def shift_by(value)
          iseq.getglobal(:$cursor)

          if value < 0
            iseq.putobject(-value)
            iseq.send(:-, 1)
          else
            iseq.putobject(value)
            iseq.send(:+, 1)
          end

          iseq.setglobal(:$cursor)
        end

        def visit_nodes(nodes)
          nodes
            .chunk do |child|
              case child
              when Increment, Decrement
                :change
              when ShiftLeft, ShiftRight
                :shift
              else
                :default
              end
            end
            .each do |type, children|
              case type
              when :change
                value = 0
                children.each { |child| value += child.is_a?(Increment) ? 1 : -1 }
                change_by(value)
              when :shift
                value = 0
                children.each { |child| value += child.is_a?(ShiftRight) ? 1 : -1 }
                shift_by(value)
              else
                visit_all(children)
              end
            end
        end
      end

      class Error < StandardError
      end

      attr_reader :source

      def initialize(source)
        @source = source
      end

      def compile
        Root.new(nodes: parse_segment(source, 0), location: 0...source.length).accept(Compiler.new)
      end

      private

      def parse_segment(segment, offset)
        index = 0
        nodes = []

        while index < segment.length
          location = offset + index

          case segment[index]
          when "+"
            nodes << Increment.new(location: location...(location + 1))
            index += 1
          when "-"
            nodes << Decrement.new(location: location...(location + 1))
            index += 1
          when ">"
            nodes << ShiftRight.new(location: location...(location + 1))
            index += 1
          when "<"
            nodes << ShiftLeft.new(location: location...(location + 1))
            index += 1
          when "."
            nodes << Output.new(location: location...(location + 1))
            index += 1
          when ","
            nodes << Input.new(location: location...(location + 1))
            index += 1
          when "["
            matched = 1
            end_index = index + 1

            while matched != 0 && end_index < segment.length
              case segment[end_index]
              when "["
                matched += 1
              when "]"
                matched -= 1
              end

              end_index += 1
            end

            raise Error, "Unmatched start loop" if matched != 0

            content = segment[(index + 1)...(end_index - 1)]
            nodes << Loop.new(
              nodes: parse_segment(content, offset + index + 1),
              location: location...(offset + end_index)
            )

            index = end_index
          when "]"
            raise Error, "Unmatched end loop"
          else
            index += 1
          end
        end

        nodes
      end
    end
  end
end
