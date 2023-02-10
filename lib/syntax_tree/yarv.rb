# frozen_string_literal: true

require "stringio"

require_relative "yarv/basic_block"
require_relative "yarv/bf"
require_relative "yarv/calldata"
require_relative "yarv/compiler"
require_relative "yarv/control_flow_graph"
require_relative "yarv/data_flow_graph"
require_relative "yarv/decompiler"
require_relative "yarv/disassembler"
require_relative "yarv/instruction_sequence"
require_relative "yarv/instructions"
require_relative "yarv/legacy"
require_relative "yarv/local_table"
require_relative "yarv/sea_of_nodes"
require_relative "yarv/assembler"
require_relative "yarv/vm"

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    # Compile the given source into a YARV instruction sequence.
    def self.compile(source, options = Compiler::Options.new)
      SyntaxTree.parse(source).accept(Compiler.new(options))
    end

    # Compile and interpret the given source.
    def self.interpret(source, options = Compiler::Options.new)
      iseq = RubyVM::InstructionSequence.compile(source, **options)
      iseq = InstructionSequence.from(iseq.to_a)
      VM.new.run_top_frame(iseq)
    end
  end
end
