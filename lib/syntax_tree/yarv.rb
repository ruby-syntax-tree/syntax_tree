# frozen_string_literal: true

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
