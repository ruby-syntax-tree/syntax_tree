# frozen_string_literal: true

require_relative "../test_helper"
require "syntax_tree/language_server"

module SyntaxTree
  class LanguageServer
    class InlayHintsTest < Minitest::Test
      def test_assignments_in_parameters
        hints = find("def foo(a = b = c); end")

        assert_equal(1, hints.before.length)
        assert_equal(1, hints.after.length)
      end

      def test_operators_in_binaries
        hints = find("1 + 2 * 3")

        assert_equal(1, hints.before.length)
        assert_equal(1, hints.after.length)
      end

      def test_binaries_in_assignments
        hints = find("a = 1 + 2")

        assert_equal(1, hints.before.length)
        assert_equal(1, hints.after.length)
      end

      def test_nested_ternaries
        hints = find("a ? b : c ? d : e")

        assert_equal(1, hints.before.length)
        assert_equal(1, hints.after.length)
      end

      def test_bare_rescue
        hints = find("begin; rescue; end")

        assert_equal(1, hints.after.length)
      end

      def test_unary_in_binary
        hints = find("-a + b")

        assert_equal(1, hints.before.length)
        assert_equal(1, hints.after.length)
      end

      private

      def find(source)
        InlayHints.find(SyntaxTree.parse(source))
      end
    end
  end
end
