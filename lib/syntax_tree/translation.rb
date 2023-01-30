# frozen_string_literal: true

module SyntaxTree
  # This module is responsible for translating the Syntax Tree syntax tree into
  # other representations.
  module Translation
    # This method translates the given node into the representation defined by
    # the whitequark/parser gem. We don't explicitly list it as a dependency
    # because it's not required for the core functionality of Syntax Tree.
    def self.to_parser(node, source)
      require "parser"
      require_relative "translation/parser"

      buffer = ::Parser::Source::Buffer.new("(string)")
      buffer.source = source

      node.accept(Parser.new(buffer))
    end
  end
end
