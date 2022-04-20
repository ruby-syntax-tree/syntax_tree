# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class FormattingTest < Minitest::Test
    Fixtures.each_fixture do |fixture|
      define_method(:"test_formatted_#{fixture.name}") do
        assert_equal(fixture.formatted, SyntaxTree.format(fixture.source))
      end
    end

    def test_format_class_level
      source = "1+1"
      assert_equal("1 + 1\n", SyntaxTree::Formatter.format(source, SyntaxTree.parse(source)))
    end
  end
end
