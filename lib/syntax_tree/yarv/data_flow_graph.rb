# frozen_string_literal: true

module SyntaxTree
  module YARV
    # Constructs a data-flow-graph of a YARV instruction sequence, via a
    # control-flow-graph. Data flow is discovered locally and then globally. The
    # graph only considers data flow through the stack - local variables and
    # objects are considered fully escaped in this analysis.
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

      attr_reader :cfg, :insn_flows, :block_flows

      def initialize(cfg, insn_flows, block_flows)
        @cfg = cfg
        @insn_flows = insn_flows
        @block_flows = block_flows
      end

      def disasm
        fmt = Disassembler.new(cfg.iseq)
        fmt.output.puts("== dfg: #{cfg.iseq.inspect}")

        cfg.blocks.each do |block|
          fmt.output.puts(block.id)
          fmt.with_prefix("    ") do
            unless block.incoming_blocks.empty?
              from = block.incoming_blocks.map(&:id).join(", ")
              fmt.output.puts("#{fmt.current_prefix}== from: #{from}")
            end

            block_flow = block_flows.fetch(block.id)
            unless block_flow.in.empty?
              fmt.output.puts("#{fmt.current_prefix}== in: #{block_flow.in.join(", ")}")
            end

            fmt.format_insns!(block.insns, block.block_start) do |insn, length|
              insn_flow = insn_flows[length]
              next if insn_flow.in.empty? && insn_flow.out.empty?
  
              fmt.output.print(" # ")
              unless insn_flow.in.empty?
                fmt.output.print("in: #{insn_flow.in.join(", ")}")
                fmt.output.print("; ") unless insn_flow.out.empty?
              end
  
              unless insn_flow.out.empty?
                fmt.output.print("out: #{insn_flow.out.join(", ")}")
              end
            end

            to = block.outgoing_blocks.map(&:id)
            to << "leaves" if block.insns.last.leaves?
            fmt.output.puts("#{fmt.current_prefix}== to: #{to.join(", ")}")

            unless block_flow.out.empty?
              fmt.output.puts("#{fmt.current_prefix}== out: #{block_flow.out.join(", ")}")
            end  
          end
        end

        fmt.string
      end

      # Verify that we constructed the data flow graph correctly.
      def verify
        # Check that the first block has no arguments.
        raise unless block_flows.fetch(cfg.blocks.first.id).in.empty?

        # Check all control flow edges between blocks pass the right number of
        # arguments.
        cfg.blocks.each do |block|
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
        attr_reader :cfg, :insn_flows, :block_flows

        def initialize(cfg)
          @cfg = cfg

          # This data structure will hold the data flow between instructions
          # within individual basic blocks.
          @insn_flows = {}
          cfg.insns.each_key do |length|
            @insn_flows[length] = DataFlow.new
          end

          # This data structure will hold the data flow between basic blocks.
          @block_flows = {}
          cfg.blocks.each do |block|
            @block_flows[block.id] = DataFlow.new
          end
        end

        def compile
          find_local_flow
          find_global_flow
          DataFlowGraph.new(cfg, insn_flows, block_flows).tap(&:verify)
        end

        private

        # Find the data flow within each basic block. Using an abstract stack,
        # connect from consumers of data to the producers of that data.
        def find_local_flow
          cfg.blocks.each do |block|
            block_flow = block_flows.fetch(block.id)
            stack = []

            # Go through each instruction in the block...
            block.each_with_length do |insn, length|
              insn_flow = insn_flows[length]

              # How many values will be missing from the local stack to run this
              # instruction?
              missing = insn.pops - stack.size

              # For every value the instruction pops off the stack...
              insn.pops.times do
                # Was the value it pops off from another basic block?
                if stack.empty?
                  # This is a basic block argument.
                  missing -= 1
                  name = :"in_#{missing}"

                  insn_flow.in.unshift(name)
                  block_flow.in.unshift(name)
                else
                  # Connect this consumer to the producer of the value.
                  insn_flow.in.unshift(stack.pop)
                end
              end

              # Record on our abstract stack that this instruction pushed
              # this value onto the stack.
              insn.pushes.times { stack << length }
            end

            # Values that are left on the stack after going through all
            # instructions are arguments to the basic block that we jump to.
            stack.reverse_each.with_index do |producer, index|
              block_flow.out << producer
              insn_flows[producer].out << :"out_#{index}"
            end
          end

          # Go backwards and connect from producers to consumers.
          cfg.insns.each_key do |length|
            # For every instruction that produced a value used in this
            # instruction...
            insn_flows[length].in.each do |producer|
              # If it's actually another instruction and not a basic block
              # argument...
              if producer.is_a?(Integer)
                # Record in the producing instruction that it produces a value
                # used by this construction.
                insn_flows[producer].out << length
              end
            end
          end
        end

        # Find the data that flows between basic blocks.
        def find_global_flow
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
                  name = :"pass_#{index}"

                  incoming_flow.in.unshift(name)
                  incoming_flow.out.unshift(name)
                end

                # Since we modified the incoming block, add it back to the stack
                # so it'll be considered as an outgoing block again, and
                # propogate the global data flow back up the control flow graph.
                stack << incoming_block
              end
            end
          end
        end
      end
    end
  end
end
