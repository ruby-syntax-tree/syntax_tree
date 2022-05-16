# frozen_string_literal: true

require_relative "../test_helper"
require "syntax_tree/formatter/single_quotes"

module SyntaxTree
  class Formatter
    class SingleQuotesTest < Minitest::Test
      class TestFormatter < Formatter
        prepend Formatter::SingleQuotes
      end

      def test_empty_string_literal
        assert_format("''\n", "\"\"")
      end

      def test_string_literal
        assert_format("'string'\n", "\"string\"")
      end

      def test_string_literal_with_interpolation
        assert_format("\"\#{foo}\"\n")
      end

      def test_dyna_symbol
        assert_format(":'symbol'\n", ":\"symbol\"")
      end

      def test_label
        assert_format(
          "{ foo => foo, :'bar' => bar }\n",
          "{ foo => foo, \"bar\": bar }"
        )
      end

      private

      def assert_format(expected, source = expected)
        formatter = TestFormatter.new(source, [])
        SyntaxTree.parse(source).format(formatter)
      
        formatter.flush
        assert_equal(expected, formatter.output.join)
      end
    end
  end
end
