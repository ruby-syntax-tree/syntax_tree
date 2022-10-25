# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SearchTest < Minitest::Test
    def test_search_binary_or
      results = search("Foo + Bar + 1", "VarRef | Int")

      assert_equal 3, results.length
      assert_equal "1", results.min_by { |node| node.class.name }.value
    end

    def test_search_const
      results = search("Foo + Bar + Baz", "VarRef")

      assert_equal 3, results.length
      assert_equal %w[Bar Baz Foo], results.map { |node| node.value.value }.sort
    end

    def test_search_syntax_tree_const
      results = search("Foo + Bar + Baz", "SyntaxTree::VarRef")

      assert_equal 3, results.length
    end

    def test_search_hash_pattern_string
      results = search("Foo + Bar + Baz", "VarRef[value: Const[value: 'Foo']]")

      assert_equal 1, results.length
      assert_equal "Foo", results.first.value.value
    end

    def test_search_hash_pattern_regexp
      results = search("Foo + Bar + Baz", "VarRef[value: Const[value: /^Ba/]]")

      assert_equal 2, results.length
      assert_equal %w[Bar Baz], results.map { |node| node.value.value }.sort
    end

    def test_search_string_empty
      results = search("''", "StringLiteral[parts: []]")

      assert_equal 1, results.length
    end

    def test_search_symbol_empty
      results = search(":''", "DynaSymbol[parts: []]")

      assert_equal 1, results.length
    end

    private

    def search(source, query)
      pattern = Pattern.new(query).compile
      program = SyntaxTree.parse(source)

      Search.new(pattern).scan(program).to_a
    end
  end
end
