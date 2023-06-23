# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class FormattingTest < Minitest::Test
    Fixtures.each_fixture do |fixture|
      define_method(:"test_formatted_#{fixture.name}") do
        assert_equal(fixture.formatted, SyntaxTree.format(fixture.source))
        # assert_syntax_tree(SyntaxTree.parse(fixture.source))
      end
    end

    def test_format_class_level
      source = "1+1"

      assert_equal(
        "1 + 1\n",
        Formatter.format(source, SyntaxTree.parse(source))
      )
    end

    def test_stree_ignore
      source = <<~SOURCE
        # stree-ignore
        1+1
      SOURCE

      assert_equal(source, SyntaxTree.format(source))
    end

    def test_formatting_with_different_indentation_level
      source = <<~SOURCE
        def foo
          puts "a"
        end
      SOURCE

      # Default indentation
      assert_equal(source, SyntaxTree.format(source))

      # Level 2
      assert_equal(<<-EXPECTED.chomp, SyntaxTree.format(source, 80, 2).rstrip)
  def foo
    puts "a"
  end
      EXPECTED

      # Level 4
      assert_equal(<<-EXPECTED.chomp, SyntaxTree.format(source, 80, 4).rstrip)
    def foo
      puts "a"
    end
      EXPECTED

      # Level 6
      assert_equal(<<-EXPECTED.chomp, SyntaxTree.format(source, 80, 6).rstrip)
      def foo
        puts "a"
      end
      EXPECTED
    end
  end
end
