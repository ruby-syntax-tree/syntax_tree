# frozen_string_literal: true

require_relative "../test_helper"
require "syntax_tree/language_server"

module SyntaxTree
  class LanguageServer
    class InlayHintsTest < Minitest::Test
      def test_assignments_in_parameters
        assert_hints(2, "def foo(a = b = c); end")
      end

      def test_operators_in_binaries
        assert_hints(2, "1 + 2 * 3")
      end

      def test_binaries_in_assignments
        assert_hints(2, "a = 1 + 2")
      end

      def test_nested_ternaries
        assert_hints(2, "a ? b : c ? d : e")
      end

      def test_bare_rescue
        assert_hints(1, "begin; rescue; end")
      end

      def test_unary_in_binary
        assert_hints(2, "-a + b")
      end

      private

      def assert_hints(expected, source)
        visitor = InlayHints.new
        SyntaxTree.parse(source).accept(visitor)

        assert_equal(expected, visitor.hints.length)
      end
    end
  end
end
