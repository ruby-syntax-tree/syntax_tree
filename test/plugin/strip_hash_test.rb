# frozen_string_literal: true

require_relative "../test_helper"

module SyntaxTree
  class StripHashTest < Minitest::Test
    def test_single_hash
      assert_format("{foo: 1}\n")
    end

    def test_multi_line_hash
      assert_format(<<~EXPECTED)
        {
          fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo: 1,
          baaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaaa: 2
        }
      EXPECTED
    end

    private

    def assert_format(expected, source = expected)
      options = Formatter::Options.new(strip_hash: true)
      formatter = Formatter.new(source, [], options: options)
      SyntaxTree.parse(source).format(formatter)

      formatter.flush
      assert_equal(expected, formatter.output.join)
    end
  end
end
