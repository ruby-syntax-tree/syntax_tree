# frozen_string_literal: true

require_relative "../test_helper"

module SyntaxTree
  class DisableTernaryTest < Minitest::Test
    def test_short_if_else_unchanged
      assert_format(<<~RUBY)
        if true
          1
        else
          2
        end
      RUBY
    end

    def test_short_ternary_unchanged
      assert_format("true ? 1 : 2\n")
    end

    private

    def assert_format(expected, source = expected)
      options = Formatter::Options.new(disable_auto_ternary: true)
      formatter = Formatter.new(source, [], options: options)
      SyntaxTree.parse(source).format(formatter)

      formatter.flush
      assert_equal(expected, formatter.output.join)
    end
  end
end
