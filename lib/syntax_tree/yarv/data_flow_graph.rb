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

      def self.compile(cfg)
        # First, create a data structure to encode data flow between
        # instructions.
        insn_flows = {}
        cfg.insns.each_with_index do |insn, index|
          insn_flows[index] = DataFlow.new
        end

        # Next, create a data structure to encode data flow between basic
        # blocks.
        block_flows = {}
        cfg.blocks.each do |block|
          block_flows[block.block_start] = DataFlow.new
        end

        # Now, discover the data flow within each basic block. Using an abstract
        # stack, connect from consumers of data to the producers of that data.
        cfg.blocks.each do |block|
          block_flow = block_flows.fetch(block.block_start)

          stack = []
          stack_initial_depth = 0

          # Go through each instruction in the block...
          block.insns.each.with_index(block.block_start) do |insn, index|
            insn_flow = insn_flows[index]

            # How many values will be missing from the local stack to run this
            # instruction?
            missing_stack_values = insn.pops - stack.size

            # For every value the instruction pops off the stack...
            insn.pops.times do
              # Was the value it pops off from another basic block?
              if stack.empty?
                # This is a basic block argument.
                name = :"in_#{missing_stack_values - 1}"

                insn_flow.in.unshift(name)
                block_flow.in.unshift(name)

                stack_initial_depth += 1
                missing_stack_values -= 1
              else
                # Connect this consumer to the producer of the value.
                insn_flow.in.unshift(stack.pop)
              end
            end

            # Record on our abstract stack that this instruction pushed
            # this value onto the stack.
            insn.pushes.times { stack << index }
          end

          # Values that are left on the stack after going through all
          # instructions are arguments to the basic block that we jump to.
          stack.reverse_each.with_index do |producer, index|
            block_flow.out << producer
            insn_flows[producer].out << :"out_#{index}"
          end
        end

        # Go backwards and connect from producers to consumers.
        cfg.insns.each_with_index do |insn, index|
          # For every instruction that produced a value used in this
          # instruction...
          insn_flows[index].in.each do |producer|
            # If it's actually another instruction and not a basic block
            # argument...
            if producer.is_a?(Integer)
              # Record in the producing instruction that it produces a value
              # used by this construction.
              insn_flows[producer].out << index
            end
          end
        end

        # Now, discover the data flow between basic blocks.
        stack = [*cfg.blocks]
        until stack.empty?
          succ = stack.pop
          succ_flow = block_flows.fetch(succ.block_start)
          succ.predecessors.each do |pred|
            pred_flow = block_flows.fetch(pred.block_start)

            # Does a predecessor block have fewer outputs than the successor
            # has inputs?
            if pred_flow.out.size < succ_flow.in.size
              # If so then add arguments to pass data through from the
              # predecessor's predecessors.
              (succ_flow.in.size - pred_flow.out.size).times do |index|
                name = :"pass_#{index}"
                pred_flow.in.unshift(name)
                pred_flow.out.unshift(name)
              end

              # Since we modified the predecessor, add it back to the worklist
              # so it'll be considered as a successor again, and propogate the
              # global data flow back up the control flow graph.
              stack << pred
            end
          end
        end

        # Verify that we constructed the data flow graph correctly. Check that
        # the first block has no arguments.
        raise unless block_flows.fetch(cfg.blocks.first.block_start).in.empty?

        # Check all control flow edges between blocks pass the right number of
        # arguments.
        cfg.blocks.each do |pred|
          pred_flow = block_flows.fetch(pred.block_start)

          if pred.successors.empty?
            # With no successors, there should be no output arguments.
            raise unless pred_flow.out.empty?
          else
            # Check with successor...
            pred.successors.each do |succ|
              succ_flow = block_flows.fetch(succ.block_start)

              # The predecessor should have as many output arguments as the
              # success has input arguments.
              raise unless pred_flow.out.size == succ_flow.in.size
            end
          end
        end

        # Finally we can return the data flow graph.
        new(cfg, insn_flows, block_flows)
      end

      def disasm
        fmt = Disassembler.new
        output = StringIO.new
        output.puts "== dfg #{cfg.iseq.name}"

        cfg.blocks.each do |block|
          output.print(block.id)
          unless block.predecessors.empty?
            output.print(" # from: #{block.predecessors.map(&:id).join(", ")}")
          end
          output.puts

          block_flow = block_flows.fetch(block.block_start)
          unless block_flow.in.empty?
            output.puts "         # in: #{block_flow.in.join(", ")}"
          end

          block.insns.each.with_index(block.block_start) do |insn, index|
            output.print("    ")
            output.print(insn.disasm(fmt))

            insn_flow = insn_flows[index]
            if insn_flow.in.empty? && insn_flow.out.empty?
              output.puts
              next
            end

            output.print(" # ")
            unless insn_flow.in.empty?
              output.print("in: #{insn_flow.in.join(", ")}")
              output.print("; ") unless insn_flow.out.empty?
            end

            unless insn_flow.out.empty?
              output.print("out: #{insn_flow.out.join(", ")}")
            end

            output.puts
          end

          successors = block.successors.map(&:id)
          successors << "leaves" if block.last.leaves?
          output.puts("        # to: #{successors.join(", ")}") unless successors.empty?

          unless block_flow.out.empty?
            output.puts "        # out: #{block_flow.out.join(", ")}"
          end
        end

        output.string
      end
    end
  end
end
