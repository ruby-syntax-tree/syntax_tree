# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class PrettyPrintVisitorTest < Minitest::Test
    Fixtures.each_fixture do |fixture|
      define_method(:"test_pretty_print_#{fixture.name}") do
        formatter = PP.new([])

        program = SyntaxTree.parse(fixture.source)
        program.pretty_print(formatter)

        formatter.flush
        refute_includes(formatter.output.join, "#<")
      end
    end
  end
end
