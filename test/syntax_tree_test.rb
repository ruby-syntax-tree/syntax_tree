# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class SyntaxTreeTest < Minitest::Test
    def test_configure
      default_print_width = SyntaxTree.options.print_width
      SyntaxTree.configure { |config| config.print_width = default_print_width }
    end

    def test_format
      assert_equal("1 + 1\n", SyntaxTree.format("1+1"))
    end

    def test_format_file
      assert_kind_of(String, SyntaxTree.format_file(__FILE__))
    end

    def test_format_print_width
      options = Options.new(print_width: 5)
      assert_equal("foo +\n  bar\n", SyntaxTree.format("foo + bar", options))
    end

    def test_format_stree_ignore
      source = <<~SOURCE
        # stree-ignore
        1+1
      SOURCE

      assert_equal(source, SyntaxTree.format(source))
    end

    def test_version
      refute_nil(VERSION)
    end

    def test_visit_methods
      expected = Prism::Visitor.public_instance_methods.grep(/\Avisit_.+_node\z/).sort
      actual = Prism::Format.public_instance_methods.grep(/\Avisit_.+_node\z/).sort

      assert_empty(expected - actual)
      assert_empty(actual - expected)
    end
  end
end
