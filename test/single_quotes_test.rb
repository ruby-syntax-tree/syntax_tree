# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SingleQuotesTest < Minitest::Test
    def test_empty_string_literal
      assert_format("''\n", "\"\"")
    end

    def test_character_literal_with_double_quote
      assert_format("'\"'\n", "?\"")
    end

    def test_character_literal_with_singlee_quote
      assert_format("'\\''\n", "?'")
    end

    def test_string_literal
      assert_format("'string'\n", "\"string\"")
    end

    def test_string_literal_with_interpolation
      assert_format("\"\#{foo}\"\n")
    end

    def test_single_quote_in_string
      assert_format("\"str'ing\"\n")
    end

    def test_label
      assert_format("{ foo => foo, :bar => bar }\n", "{ foo => foo, \"bar\": bar }")
    end

    private

    def assert_format(expected, source = expected)
      options = SyntaxTree.options(preferred_quote: "'")
      assert_equal(expected, SyntaxTree.format(source, options))
    end
  end
end
