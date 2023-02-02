# frozen_string_literal: true

module SyntaxTree
  module YARV
    # Constructs a control-flow-graph of a YARV instruction sequence. We use
    # conventional basic-blocks.
    class ControlFlowGraph
      # This object represents a single basic block, wherein all contained
      # instructions do not branch except for the last one.
      class BasicBlock
        # This is the index into the list of instructions where this block
        # starts.
        attr_reader :block_start

        # This is the set of instructions that this block contains.
        attr_reader :insns

        # This is an array of basic blocks that are predecessors to this block.
        attr_reader :preds

        # This is an array of basic blocks that are successors to this block.
        attr_reader :succs

        def initialize(block_start, insns)
          @block_start = block_start
          @insns = insns

          @preds = []
          @succs = []
        end

        def id
          "block_#{block_start}"
        end

        def last
          insns.last
        end
      end

      # This is the instruction sequence that this control flow graph
      # corresponds to.
      attr_reader :iseq

      # This is the list of instructions that this control flow graph contains.
      # It is effectively the same as the list of instructions in the
      # instruction sequence but with line numbers and events filtered out.
      attr_reader :insns

      # This is the set of basic blocks that this control-flow graph contains.
      attr_reader :blocks

      def initialize(iseq, insns, blocks)
        @iseq = iseq
        @insns = insns
        @blocks = blocks
      end

      def self.compile(iseq)
        # First, we need to find all of the instructions that immediately follow
        # labels so that when we are looking at instructions that branch we know
        # where they branch to.
        labels = {}
        insns = []

        iseq.insns.each do |insn|
          case insn
          when Instruction
            insns << insn
          when InstructionSequence::Label
            labels[insn] = insns.length
          end
        end

        # Now we need to find the indices of the instructions that start a basic
        # block because they're either:
        #
        # * the start of an instruction sequence
        # * the target of a branch
        # * fallen through to from a branch
        #
        block_starts = Set.new([0])

        insns.each_with_index do |insn, index|
          if insn.branches?
            block_starts.add(labels[insn.label]) if insn.respond_to?(:label)
            block_starts.add(index + 1) if insn.falls_through?
          end
        end

        block_starts = block_starts.to_a.sort

        # Now we can build up a set of basic blocks by iterating over the starts
        # of each block. They are keyed by the index of their first instruction.
        blocks = {}
        block_starts.each_with_index do |block_start, block_index|
          block_stop = (block_starts[(block_index + 1)..] + [insns.length]).min

          blocks[block_start] =
            BasicBlock.new(block_start, insns[block_start...block_stop])
        end

        # Now we need to connect the blocks by letting them know which blocks
        # precede them and which blocks follow them.
        blocks.each do |block_start, block|
          insn = block.last

          if insn.branches? && insn.respond_to?(:label)
            block.succs << blocks.fetch(labels[insn.label])
          end

          if (!insn.branches? && !insn.leaves?) || insn.falls_through?
            block.succs << blocks.fetch(block_start + block.insns.length)
          end

          block.succs.each { |succ| succ.preds << block }
        end

        # Here we're going to verify that we set up the control flow graph
        # correctly. To do so we will assert that the only instruction in any
        # given block that branches is the last instruction in the block.
        blocks.each_value do |block|
          block.insns[0...-1].each { |insn| raise if insn.branches? }
        end

        # Finally we can return a new control flow graph with the given
        # instruction sequence and our set of basic blocks.
        new(iseq, insns, blocks.values)
      end

      def disasm
        fmt = Disassembler.new

        output = StringIO.new
        output.puts "== cfg #{iseq.name}"

        blocks.each do |block|
          output.print(block.id)

          unless block.preds.empty?
            output.print(" # from: #{block.preds.map(&:id).join(", ")}")
          end

          output.puts

          block.insns.each do |insn|
            output.print("    ")
            output.puts(insn.disasm(fmt))
          end

          succs = block.succs.map(&:id)
          succs << "leaves" if block.last.leaves?
          output.print("        # to: #{succs.join(", ")}") unless succs.empty?

          output.puts
        end

        output.string
      end
    end
  end
end
