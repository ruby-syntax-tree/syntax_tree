# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This class represents a control flow graph of a YARV instruction sequence.
    # It constructs a graph of basic blocks that hold subsets of the list of
    # instructions from the instruction sequence.
    #
    # You can use this class by calling the ::compile method and passing it a
    # YARV instruction sequence. It will return a control flow graph object.
    #
    #     iseq = RubyVM::InstructionSequence.compile("1 + 2")
    #     iseq = SyntaxTree::YARV::InstructionSequence.from(iseq.to_a)
    #     cfg = SyntaxTree::YARV::ControlFlowGraph.compile(iseq)
    #
    class ControlFlowGraph
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

      def disasm
        fmt = Disassembler.new
        output = StringIO.new
        output.puts "== cfg #{iseq.name}"

        blocks.each do |block|
          output.print(block.id)

          unless block.predecessors.empty?
            output.print(" # from: #{block.predecessors.map(&:id).join(", ")}")
          end

          output.puts

          block.insns.each do |insn|
            output.print("    ")
            output.puts(insn.disasm(fmt))
          end

          successors = block.successors.map(&:id)
          successors << "leaves" if block.insns.last.leaves?
          output.print("        # to: #{successors.join(", ")}") unless successors.empty?

          output.puts
        end

        output.string
      end

      # This method is used to verify that the control flow graph is well
      # formed. It does this by checking that each basic block is itself well
      # formed.
      def verify
        blocks.each(&:verify)
      end

      def self.compile(iseq)
        Compiler.new(iseq).compile
      end

      # This object represents a single basic block, wherein all contained
      # instructions do not branch except for the last one.
      class BasicBlock
        # This is the unique identifier for this basic block.
        attr_reader :id

        # This is the index into the list of instructions where this block
        # starts.
        attr_reader :block_start

        # This is the set of instructions that this block contains.
        attr_reader :insns

        # This is an array of basic blocks that are predecessors to this block.
        attr_reader :predecessors

        # This is an array of basic blocks that are successors to this block.
        attr_reader :successors

        def initialize(block_start, insns)
          @id = "block_#{block_start}"

          @block_start = block_start
          @insns = insns

          @predecessors = []
          @successors = []
        end

        # Yield each instruction in this basic block along with its index from
        # the original instruction sequence.
        def each_with_index(&block)
          insns.each.with_index(block_start, &block)
        end

        # This method is used to verify that the basic block is well formed. It
        # checks that the only instruction in this basic block that branches is
        # the last instruction.
        def verify
          insns[0...-1].each { |insn| raise unless insn.branch_targets.empty? }
        end
      end

      # This class is responsible for creating a control flow graph from the
      # given instruction sequence.
      class Compiler
        attr_reader :iseq, :labels, :insns

        def initialize(iseq)
          @iseq = iseq

          # We need to find all of the instructions that immediately follow
          # labels so that when we are looking at instructions that branch we
          # know where they branch to.
          @labels = {}
          @insns = []

          iseq.insns.each do |insn|
            case insn
            when Instruction
              @insns << insn
            when InstructionSequence::Label
              @labels[insn] = @insns.length
            end
          end
        end

        # This method is used to compile the instruction sequence into a control
        # flow graph. It returns an instance of ControlFlowGraph.
        def compile
          blocks = connect_basic_blocks(build_basic_blocks)
          ControlFlowGraph.new(iseq, insns, blocks.values).tap(&:verify)
        end

        private

        # Finds the indices of the instructions that start a basic block because
        # they're either:
        #
        # * the start of an instruction sequence
        # * the target of a branch
        # * fallen through to from a branch
        #
        def find_basic_block_starts
          block_starts = Set.new([0])

          insns.each_with_index do |insn, index|
            branch_targets = insn.branch_targets

            if branch_targets.any?
              branch_targets.each do |branch_target|
                block_starts.add(labels[branch_target])
              end

              block_starts.add(index + 1) if insn.falls_through?
            end
          end

          block_starts.to_a.sort
        end

        # Builds up a set of basic blocks by iterating over the starts of each
        # block. They are keyed by the index of their first instruction.
        def build_basic_blocks
          block_starts = find_basic_block_starts

          block_starts.each_with_index.to_h do |block_start, block_index|
            block_end = (block_starts[(block_index + 1)..] + [insns.length]).min
            block_insns = insns[block_start...block_end]

            [block_start, BasicBlock.new(block_start, block_insns)]
          end
        end

        # Connect the blocks by letting them know which blocks precede them and
        # which blocks succeed them.
        def connect_basic_blocks(blocks)
          blocks.each do |block_start, block|
            insn = block.insns.last

            insn.branch_targets.each do |branch_target|
              block.successors << blocks.fetch(labels[branch_target])
            end

            if (insn.branch_targets.empty? && !insn.leaves?) || insn.falls_through?
              block.successors << blocks.fetch(block_start + block.insns.length)
            end

            block.successors.each do |successor|
              successor.predecessors << block
            end
          end
        end
      end
    end
  end
end
