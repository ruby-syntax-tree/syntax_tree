# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This object represents a single basic block, wherein all contained
    # instructions do not branch except for the last one.
    class BasicBlock
      # This is the unique identifier for this basic block.
      attr_reader :id

      # This is the index into the list of instructions where this block starts.
      attr_reader :block_start

      # This is the set of instructions that this block contains.
      attr_reader :insns

      # This is an array of basic blocks that lead into this block.
      attr_reader :incoming_blocks

      # This is an array of basic blocks that this block leads into.
      attr_reader :outgoing_blocks

      def initialize(block_start, insns)
        @id = "block_#{block_start}"

        @block_start = block_start
        @insns = insns

        @incoming_blocks = []
        @outgoing_blocks = []
      end

      # Yield each instruction in this basic block along with its index from the
      # original instruction sequence.
      def each_with_length
        return enum_for(:each_with_length) unless block_given?

        length = block_start
        insns.each do |insn|
          yield insn, length
          length += insn.length
        end
      end

      # This method is used to verify that the basic block is well formed. It
      # checks that the only instruction in this basic block that branches is
      # the last instruction.
      def verify
        insns[0...-1].each { |insn| raise unless insn.branch_targets.empty? }
      end
    end
  end
end
