# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SyntaxTreeTest < Minitest::Test
    def test_empty
      void_stmt = SyntaxTree.parse("").statements.body.first
      assert_kind_of(VoidStmt, void_stmt)
    end

    def test_multibyte
      assign = SyntaxTree.parse("🎉 + 🎉").statements.body.first
      assert_equal(5, assign.location.end_char)
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

    def test_parse_error
      assert_raises(Parser::ParseError) { SyntaxTree.parse("<>") }
    end

    def test_maxwidth_format
      assert_equal("foo +\n  bar\n", SyntaxTree.format("foo + bar", 5))
    end

    def test_read
      source = SyntaxTree.read(__FILE__)
      assert_equal(Encoding.default_external, source.encoding)

      source = SyntaxTree.read(File.expand_path("encoded.rb", __dir__))
      assert_equal(Encoding::Shift_JIS, source.encoding)
    end

    def test_version
      refute_nil(VERSION)
    end
  end
end
