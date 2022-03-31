# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class BehaviorTest < Minitest::Test
    def test_empty
      void_stmt = SyntaxTree.parse("").statements.body.first
      assert_kind_of(VoidStmt, void_stmt)
    end

    def test_multibyte
      assign = SyntaxTree.parse("🎉 + 🎉").statements.body.first
      assert_equal(5, assign.location.end_char)
    end

    def test_parse_error
      assert_raises(Parser::ParseError) { SyntaxTree.parse("<>") }
    end

    def test_next_statement_start
      source = <<~SOURCE
        def method # comment
          expression
        end
      SOURCE

      bodystmt = SyntaxTree.parse(source).statements.body.first.bodystmt
      assert_equal(20, bodystmt.location.start_char)
    end

    def test_version
      refute_nil(VERSION)
    end
  end
end
