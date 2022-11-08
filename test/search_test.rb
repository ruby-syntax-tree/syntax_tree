# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SearchTest < Minitest::Test
    def test_search_invalid_syntax
      assert_raises(Pattern::CompilationError) { search("", "<>") }
    end

    def test_search_invalid_constant
      assert_raises(Pattern::CompilationError) { search("", "Foo") }
    end

    def test_search_invalid_nested_constant
      assert_raises(Pattern::CompilationError) { search("", "Foo::Bar") }
    end

    def test_search_regexp_with_interpolation
      assert_raises(Pattern::CompilationError) { search("", "/\#{foo}/") }
    end

    def test_search_string_with_interpolation
      assert_raises(Pattern::CompilationError) { search("", '"#{foo}"') }
    end

    def test_search_symbol_with_interpolation
      assert_raises(Pattern::CompilationError) { search("", ":\"\#{foo}\"") }
    end

    def test_search_invalid_node
      assert_raises(Pattern::CompilationError) { search("", "Int[^foo]") }
    end

    def test_search_self
      assert_raises(Pattern::CompilationError) { search("", "self") }
    end

    def test_search_array_pattern_no_constant
      results = search("1 + 2", "[Int, Int]")

      assert_equal 1, results.length
    end

    def test_search_array_pattern
      results = search("1 + 2", "Binary[Int, Int]")

      assert_equal 1, results.length
    end

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

    def test_search_object_const
      results = search("1 + 2 + 3", "Int[value: String]")

      assert_equal 3, results.length
    end

    def test_search_syntax_tree_const
      results = search("Foo + Bar + Baz", "SyntaxTree::VarRef")

      assert_equal 3, results.length
    end

    def test_search_hash_pattern_no_constant
      results = search("Foo + Bar + Baz", "{ value: Const }")

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
      results = search("", "''")

      assert_empty results
    end

    def test_search_symbol_empty
      results = search("", ":''")

      assert_empty results
    end

    def test_search_symbol_plain
      results = search("1 + 2", "Binary[operator: :'+']")

      assert_equal 1, results.length
    end

    def test_search_symbol
      results = search("1 + 2", "Binary[operator: :+]")

      assert_equal 1, results.length
    end

    private

    def search(source, query)
      SyntaxTree.search(source, query).to_a
    end
  end
end
