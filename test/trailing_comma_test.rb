# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class TrailingCommaTest < Minitest::Test
    def test_arg_paren_flat
      assert_format("foo(a)\n")
    end

    def test_arg_paren_break
      assert_format(<<~EXPECTED, <<~SOURCE)
        foo(
          #{"a" * 80},
        )
      EXPECTED
        foo(#{"a" * 80})
      SOURCE
    end

    def test_arg_paren_block
      assert_format(<<~EXPECTED, <<~SOURCE)
        foo(
          &#{"a" * 80}
        )
      EXPECTED
        foo(&#{"a" * 80})
      SOURCE
    end

    def test_arg_paren_command
      assert_format(<<~EXPECTED, <<~SOURCE)
        foo(
          bar #{"a" * 80}
        )
      EXPECTED
        foo(bar #{"a" * 80})
      SOURCE
    end

    def test_arg_paren_command_call
      assert_format(<<~EXPECTED, <<~SOURCE)
        foo(
          bar.baz #{"a" * 80}
        )
      EXPECTED
        foo(bar.baz #{"a" * 80})
      SOURCE
    end

    def test_array_literal_flat
      assert_format("[a]\n")
    end

    def test_array_literal_break
      assert_format(<<~EXPECTED, <<~SOURCE)
        [
          #{"a" * 80},
        ]
      EXPECTED
        [#{"a" * 80}]
      SOURCE
    end

    def test_hash_literal_flat
      assert_format("{ a: a }\n")
    end

    def test_hash_literal_break
      assert_format(<<~EXPECTED, <<~SOURCE)
        {
          a:
            #{"a" * 80},
        }
      EXPECTED
        { a: #{"a" * 80} }
      SOURCE
    end

    private

    def assert_format(expected, source = expected)
      options = SyntaxTree.options(print_width: 80, trailing_comma: true)
      assert_equal(expected, SyntaxTree.format(source, options))
    end
  end
end
