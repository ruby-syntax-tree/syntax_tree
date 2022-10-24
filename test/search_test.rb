# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SearchTest < Minitest::Test
    def test_search_binary_or
      root = SyntaxTree.parse("Foo + Bar + 1")
      scanned = Search.new("VarRef | Int").scan(root).to_a

      assert_equal 3, scanned.length
      assert_equal "1", scanned.min_by { |node| node.class.name }.value
    end

    def test_search_const
      root = SyntaxTree.parse("Foo + Bar + Baz")

      scanned = Search.new("VarRef").scan(root).to_a

      assert_equal 3, scanned.length
      assert_equal %w[Bar Baz Foo], scanned.map { |node| node.value.value }.sort
    end

    def test_search_syntax_tree_const
      root = SyntaxTree.parse("Foo + Bar + Baz")

      scanned = Search.new("SyntaxTree::VarRef").scan(root).to_a

      assert_equal 3, scanned.length
    end

    def test_search_hash_pattern_string
      root = SyntaxTree.parse("Foo + Bar + Baz")

      scanned = Search.new("VarRef[value: Const[value: 'Foo']]").scan(root).to_a

      assert_equal 1, scanned.length
      assert_equal "Foo", scanned.first.value.value
    end

    def test_search_hash_pattern_regexp
      root = SyntaxTree.parse("Foo + Bar + Baz")

      query = "VarRef[value: Const[value: /^Ba/]]"
      scanned = Search.new(query).scan(root).to_a

      assert_equal 2, scanned.length
      assert_equal %w[Bar Baz], scanned.map { |node| node.value.value }.sort
    end
  end
end
