# frozen_string_literal: true

require 'test_helper'

class ParseTreeTest < Minitest::Test
  def test_multibyte
    assign = ParseTree.new('🎉 + 🎉').parse.statements.body.first
    assert_equal(5, assign.location.end_char)
  end

  def test_parse_error
    assert_raises(ParseTree::ParseError) do
      ParseTree.new('<>').parse
    end
  end

  def test_next_statement_start
    source = <<~SOURCE
      def method # comment
        expression
      end
    SOURCE

    bodystmt = ParseTree.new(source).parse.statements.body.first.bodystmt
    assert_equal(20, bodystmt.location.start_char)
  end
end
