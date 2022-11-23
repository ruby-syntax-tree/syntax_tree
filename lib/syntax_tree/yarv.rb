# frozen_string_literal: true

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    # Compile the given source into a YARV instruction sequence.
    def self.compile(source, options = Compiler::Options.new)
      SyntaxTree.parse(source).accept(Compiler.new(options))
    end
  end
end
