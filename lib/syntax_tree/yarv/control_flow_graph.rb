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
        fmt = Disassembler.new(iseq)
        fmt.output.print("== cfg: #<ISeq:#{iseq.name}@<compiled>:1 ")
        fmt.output.puts("(#{iseq.line},0)-(#{iseq.line},0)>")

        blocks.each do |block|
          fmt.output.puts(block.id)
          fmt.with_prefix("    ") do
            unless block.incoming_blocks.empty?
              from = block.incoming_blocks.map(&:id).join(", ")
              fmt.output.puts("#{fmt.current_prefix}== from: #{from}")
            end

            fmt.format_insns!(block.insns, block.block_start)

            to = block.outgoing_blocks.map(&:id)
            to << "leaves" if block.insns.last.leaves?
            fmt.output.puts("#{fmt.current_prefix}== to: #{to.join(", ")}")
          end
        end

        fmt.string
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

      # This class is responsible for creating a control flow graph from the
      # given instruction sequence.
      class Compiler
        # This is the instruction sequence that is being compiled.
        attr_reader :iseq

        # This is a hash of indices in the YARV instruction sequence that point
        # to their corresponding instruction.
        attr_reader :insns

        # This is a hash of labels that point to their corresponding index into
        # the YARV instruction sequence. Note that this is not the same as the
        # index into the list of instructions on the instruction sequence
        # object. Instead, this is the index into the C array, so it includes
        # operands.
        attr_reader :labels

        def initialize(iseq)
          @iseq = iseq

          @insns = {}
          @labels = {}

          length = 0
          iseq.insns.each do |insn|
            case insn
            when Instruction
              @insns[length] = insn
              length += insn.length
            when InstructionSequence::Label
              @labels[insn] = length
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

          insns.each do |index, insn|
            branch_targets = insn.branch_targets

            if branch_targets.any?
              branch_targets.each do |branch_target|
                block_starts.add(labels[branch_target])
              end

              block_starts.add(index + insn.length) if insn.falls_through?
            end
          end

          block_starts.to_a.sort
        end

        # Builds up a set of basic blocks by iterating over the starts of each
        # block. They are keyed by the index of their first instruction.
        def build_basic_blocks
          block_starts = find_basic_block_starts

          length = 0
          blocks =
            iseq.insns.grep(Instruction).slice_after do |insn|
              length += insn.length
              block_starts.include?(length)
            end

          block_starts.zip(blocks).to_h do |block_start, block_insns|
            [block_start, BasicBlock.new(block_start, block_insns)]
          end
        end

        # Connect the blocks by letting them know which blocks are incoming and
        # outgoing from each block.
        def connect_basic_blocks(blocks)
          blocks.each do |block_start, block|
            insn = block.insns.last

            insn.branch_targets.each do |branch_target|
              block.outgoing_blocks << blocks.fetch(labels[branch_target])
            end

            if (insn.branch_targets.empty? && !insn.leaves?) || insn.falls_through?
              fall_through_start = block_start + block.insns.sum(&:length)
              block.outgoing_blocks << blocks.fetch(fall_through_start)
            end

            block.outgoing_blocks.each do |outgoing_block|
              outgoing_block.incoming_blocks << block
            end
          end
        end
      end
    end
  end
end
