# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class QuotesTest < Minitest::Test
    def test_normalize
      content = "'aaa' \"bbb\" \\'ccc\\' \\\"ddd\\\""
      enclosing = "\""

      result = Quotes.normalize(content, enclosing)
      assert_equal "'aaa' \\\"bbb\\\" \\'ccc\\' \\\"ddd\\\"", result
    end
  end
end
