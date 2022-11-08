# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class MutationTest < Minitest::Test
    def test_mutates_based_on_patterns
      source = <<~RUBY
        if a = b
          c
        end
      RUBY

      expected = <<~RUBY
        if (a = b)
          c
        end
      RUBY

      program = SyntaxTree.parse(source).accept(build_mutation)
      assert_equal(expected, SyntaxTree::Formatter.format(source, program))
    end

    private

    def build_mutation
      SyntaxTree.mutation do |mutation|
        mutation.mutate("If[predicate: Assign | OpAssign]") do |node|
          # Get the existing If's predicate node
          predicate = node.predicate

          # Create a new predicate node that wraps the existing predicate node
          # in parentheses
          predicate =
            SyntaxTree::Paren.new(
              lparen: SyntaxTree::LParen.default,
              contents: predicate,
              location: predicate.location
            )

          # Return a copy of this node with the new predicate
          node.copy(predicate: predicate)
        end
      end
    end
  end
end
