# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class IndexTest < Minitest::Test
    def test_module
      index_each("module Foo; end") do |entry|
        assert_equal :Foo, entry.name
        assert_empty entry.nesting
      end
    end

    def test_module_nested
      index_each("module Foo; module Bar; end; end") do |entry|
        assert_equal :Bar, entry.name
        assert_equal [:Foo], entry.nesting
      end
    end

    def test_module_comments
      index_each("# comment1\n# comment2\nmodule Foo; end") do |entry|
        assert_equal :Foo, entry.name
        assert_equal ["# comment1", "# comment2"], entry.comments.to_a
      end
    end

    def test_class
      index_each("class Foo; end") do |entry|
        assert_equal :Foo, entry.name
        assert_empty entry.nesting
      end
    end

    def test_class_nested
      index_each("class Foo; class Bar; end; end") do |entry|
        assert_equal :Bar, entry.name
        assert_equal [:Foo], entry.nesting
      end
    end

    def test_class_comments
      index_each("# comment1\n# comment2\nclass Foo; end") do |entry|
        assert_equal :Foo, entry.name
        assert_equal ["# comment1", "# comment2"], entry.comments.to_a
      end
    end

    def test_method
      index_each("def foo; end") do |entry|
        assert_equal :foo, entry.name
        assert_empty entry.nesting
      end
    end

    def test_method_nested
      index_each("class Foo; def foo; end; end") do |entry|
        assert_equal :foo, entry.name
        assert_equal [:Foo], entry.nesting
      end
    end

    def test_method_comments
      index_each("# comment1\n# comment2\ndef foo; end") do |entry|
        assert_equal :foo, entry.name
        assert_equal ["# comment1", "# comment2"], entry.comments.to_a
      end
    end

    private

    def index_each(source)
      yield SyntaxTree::Index::ParserBackend.new.index(source).last

      if defined?(RubyVM::InstructionSequence)
        yield SyntaxTree::Index::ISeqBackend.new.index(source).last
      end
    end
  end
end
