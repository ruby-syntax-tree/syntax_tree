# frozen_string_literal: true

module SyntaxTree
  # This module is responsible for translating the Syntax Tree syntax tree into
  # other representations.
  module Translation
    # This method translates the given node into the representation defined by
    # the whitequark/parser gem. We don't explicitly list it as a dependency
    # because it's not required for the core functionality of Syntax Tree.
    def self.to_parser(node, buffer)
      require "parser"
      require_relative "translation/parser"

      node.accept(Parser.new(buffer))
    end

    # This method translates the given node into the representation defined by
    # the rubocop/rubocop-ast gem. We don't explicitly list it as a dependency
    # because it's not required for the core functionality of Syntax Tree.
    def self.to_rubocop_ast(node, buffer)
      require "rubocop/ast"
      require_relative "translation/parser"
      require_relative "translation/rubocop_ast"

      node.accept(RuboCopAST.new(buffer))
    end
  end
end
