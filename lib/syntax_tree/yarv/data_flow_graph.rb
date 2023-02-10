# frozen_string_literal: true

module SyntaxTree
  module YARV
    # Constructs a data-flow-graph of a YARV instruction sequence, via a
    # control-flow-graph. Data flow is discovered locally and then globally. The
    # graph only considers data flow through the stack - local variables and
    # objects are considered fully escaped in this analysis.
    #
    # You can use this class by calling the ::compile method and passing it a
    # control flow graph. It will return a data flow graph object.
    #
    #     iseq = RubyVM::InstructionSequence.compile("1 + 2")
    #     iseq = SyntaxTree::YARV::InstructionSequence.from(iseq.to_a)
    #     cfg = SyntaxTree::YARV::ControlFlowGraph.compile(iseq)
    #     dfg = SyntaxTree::YARV::DataFlowGraph.compile(cfg)
    #
    class DataFlowGraph
      # This object represents the flow of data between instructions.
      class DataFlow
        attr_reader :in
        attr_reader :out

        def initialize
          @in = []
          @out = []
        end
      end

      # This represents an object that goes on the stack that is passed between
      # basic blocks.
      class BlockArgument
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def local?
          false
        end

        def to_str
          name.to_s
        end
      end

      # This represents an object that goes on the stack that is passed between
      # instructions within a basic block.
      class LocalArgument
        attr_reader :name, :length

        def initialize(length)
          @length = length
        end

        def local?
          true
        end

        def to_str
          length.to_s
        end
      end

      attr_reader :cfg, :insn_flows, :block_flows

      def initialize(cfg, insn_flows, block_flows)
        @cfg = cfg
        @insn_flows = insn_flows
        @block_flows = block_flows
      end

      def blocks
        cfg.blocks
      end

      def disasm
        fmt = Disassembler.new(cfg.iseq)
        fmt.puts("== dfg: #{cfg.iseq.inspect}")

        blocks.each do |block|
          fmt.puts(block.id)
          fmt.with_prefix("    ") do |prefix|
            unless block.incoming_blocks.empty?
              from = block.incoming_blocks.map(&:id)
              fmt.puts("#{prefix}== from: #{from.join(", ")}")
            end

            block_flow = block_flows.fetch(block.id)
            unless block_flow.in.empty?
              fmt.puts("#{prefix}== in: #{block_flow.in.join(", ")}")
            end

            fmt.format_insns!(block.insns, block.block_start) do |_, length|
              insn_flow = insn_flows[length]
              next if insn_flow.in.empty? && insn_flow.out.empty?

              fmt.print(" # ")
              unless insn_flow.in.empty?
                fmt.print("in: #{insn_flow.in.join(", ")}")
                fmt.print("; ") unless insn_flow.out.empty?
              end

              unless insn_flow.out.empty?
                fmt.print("out: #{insn_flow.out.join(", ")}")
              end
            end

            to = block.outgoing_blocks.map(&:id)
            to << "leaves" if block.insns.last.leaves?
            fmt.puts("#{prefix}== to: #{to.join(", ")}")

            unless block_flow.out.empty?
              fmt.puts("#{prefix}== out: #{block_flow.out.join(", ")}")
            end
          end
        end

        fmt.string
      end

      def to_son
        SeaOfNodes.compile(self)
      end

      def to_mermaid
        Mermaid.flowchart do |flowchart|
          disasm = Disassembler::Squished.new

          blocks.each do |block|
            block_flow = block_flows.fetch(block.id)
            graph_name =
              if block_flow.in.any?
                "#{block.id} #{block_flows[block.id].in.join(", ")}"
              else
                block.id
              end

            flowchart.subgraph(graph_name) do
              previous = nil

              block.each_with_length do |insn, length|
                node =
                  flowchart.node(
                    "node_#{length}",
                    "%04d %s" % [length, insn.disasm(disasm)],
                    shape: :rounded
                  )

                flowchart.link(previous, node, color: :red) if previous
                insn_flows[length].in.each do |input|
                  if input.is_a?(LocalArgument)
                    from = flowchart.fetch("node_#{input.length}")
                    flowchart.link(from, node, color: :green)
                  end
                end

                previous = node
              end
            end
          end

          blocks.each do |block|
            block.outgoing_blocks.each do |outgoing|
              offset =
                block.block_start + block.insns.sum(&:length) -
                  block.insns.last.length

              from = flowchart.fetch("node_#{offset}")
              to = flowchart.fetch("node_#{outgoing.block_start}")
              flowchart.link(from, to, color: :red)
            end
          end
        end
      end

      # Verify that we constructed the data flow graph correctly.
      def verify
        # Check that the first block has no arguments.
        raise unless block_flows.fetch(blocks.first.id).in.empty?

        # Check all control flow edges between blocks pass the right number of
        # arguments.
        blocks.each do |block|
          block_flow = block_flows.fetch(block.id)

          if block.outgoing_blocks.empty?
            # With no outgoing blocks, there should be no output arguments.
            raise unless block_flow.out.empty?
          else
            # Check with outgoing blocks...
            block.outgoing_blocks.each do |outgoing_block|
              outgoing_flow = block_flows.fetch(outgoing_block.id)

              # The block should have as many output arguments as the
              # outgoing block has input arguments.
              raise unless block_flow.out.size == outgoing_flow.in.size
            end
          end
        end
      end

      def self.compile(cfg)
        Compiler.new(cfg).compile
      end

      # This class is responsible for creating a data flow graph from the given
      # control flow graph.
      class Compiler
        # This is the control flow graph that is being compiled.
        attr_reader :cfg

        # This data structure will hold the data flow between instructions
        # within individual basic blocks.
        attr_reader :insn_flows

        # This data structure will hold the data flow between basic blocks.
        attr_reader :block_flows

        def initialize(cfg)
          @cfg = cfg
          @insn_flows = cfg.insns.to_h { |length, _| [length, DataFlow.new] }
          @block_flows = cfg.blocks.to_h { |block| [block.id, DataFlow.new] }
        end

        def compile
          find_internal_flow
          find_external_flow
          DataFlowGraph.new(cfg, insn_flows, block_flows).tap(&:verify)
        end

        private

        # Find the data flow within each basic block. Using an abstract stack,
        # connect from consumers of data to the producers of that data.
        def find_internal_flow
          cfg.blocks.each do |block|
            block_flow = block_flows.fetch(block.id)
            stack = []

            # Go through each instruction in the block.
            block.each_with_length do |insn, length|
              insn_flow = insn_flows[length]

              # How many values will be missing from the local stack to run this
              # instruction? This will be used to determine if the values that
              # are being used by this instruction are coming from previous
              # instructions or from previous basic blocks.
              missing = insn.pops - stack.size

              # For every value the instruction pops off the stack.
              insn.pops.times do
                # Was the value it pops off from another basic block?
                if stack.empty?
                  # If the stack is empty, then there aren't enough values being
                  # pushed from previous instructions to fulfill the needs of
                  # this instruction. In that case the values must be coming
                  # from previous basic blocks.
                  missing -= 1
                  argument = BlockArgument.new(:"in_#{missing}")

                  insn_flow.in.unshift(argument)
                  block_flow.in.unshift(argument)
                else
                  # Since there are values in the stack, we can connect this
                  # consumer to the producer of the value.
                  insn_flow.in.unshift(stack.pop)
                end
              end

              # Record on our abstract stack that this instruction pushed
              # this value onto the stack.
              insn.pushes.times { stack << LocalArgument.new(length) }
            end

            # Values that are left on the stack after going through all
            # instructions are arguments to the basic block that we jump to.
            stack.reverse_each.with_index do |producer, index|
              block_flow.out << producer

              argument = BlockArgument.new(:"out_#{index}")
              insn_flows[producer.length].out << argument
            end
          end

          # Go backwards and connect from producers to consumers.
          cfg.insns.each_key do |length|
            # For every instruction that produced a value used in this
            # instruction...
            insn_flows[length].in.each do |producer|
              # If it's actually another instruction and not a basic block
              # argument...
              if producer.is_a?(LocalArgument)
                # Record in the producing instruction that it produces a value
                # used by this construction.
                insn_flows[producer.length].out << LocalArgument.new(length)
              end
            end
          end
        end

        # Find the data that flows between basic blocks.
        def find_external_flow
          stack = [*cfg.blocks]

          until stack.empty?
            block = stack.pop
            block_flow = block_flows.fetch(block.id)

            block.incoming_blocks.each do |incoming_block|
              incoming_flow = block_flows.fetch(incoming_block.id)

              # Does a predecessor block have fewer outputs than the successor
              # has inputs?
              if incoming_flow.out.size < block_flow.in.size
                # If so then add arguments to pass data through from the
                # incoming block's incoming blocks.
                (block_flow.in.size - incoming_flow.out.size).times do |index|
                  name = BlockArgument.new(:"pass_#{index}")

                  incoming_flow.in.unshift(name)
                  incoming_flow.out.unshift(name)
                end

                # Since we modified the incoming block, add it back to the stack
                # so it'll be considered as an outgoing block again, and
                # propogate the external data flow back up the control flow
                # graph.
                stack << incoming_block
              end
            end
          end
        end
      end
    end
  end
end
