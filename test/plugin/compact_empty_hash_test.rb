# frozen_string_literal: true

require_relative "../test_helper"

module SyntaxTree
  class CompactEmptyHashTest < Minitest::Test
    def test_empty_hash
      assert_format("{}\n", "{}")
    end

    def test_empty_hash_with_spaces
      assert_format("{}\n", "{ }")
    end

    def test_empty_hash_with_newlines
      assert_format("{}\n", "{\n}")
    end

    def test_empty_hash_in_assignment
      assert_format("x = {}\n", "x = {}")
    end

    def test_empty_hash_in_method_call
      assert_format("method({})\n", "method({})")
    end

    def test_empty_hash_in_array
      assert_format("[{}]\n", "[{}]")
    end

    def test_long_assignment_with_empty_hash
      source = "this_is_a_very_long_variable_name_that_might_cause_line_breaks_when_assigned_an_empty_hash = {}"
      expected = "this_is_a_very_long_variable_name_that_might_cause_line_breaks_when_assigned_an_empty_hash = {}\n"
      assert_format(expected, source)
    end

    def test_empty_hash_values_in_multiline_hash
      source = "{ very_long_key_name_that_might_cause_issues: {}, another_very_long_key_name: {}, yet_another_key: {} }"
      expected = <<~RUBY
        {
          very_long_key_name_that_might_cause_issues: {},
          another_very_long_key_name: {},
          yet_another_key: {}
        }
      RUBY
      assert_format(expected, source)
    end

    def test_non_empty_hash_still_works
      source = "{ key: value }"
      expected = "{ key: value }\n"
      assert_format(expected, source)
    end

    def test_without_plugin_allows_multiline_empty_hash
      source = "this_is_a_very_long_variable_name_that_might_cause_line_breaks_when_assigned_an_empty_hash = {}"

      # Format without the compact_empty_hash option
      options = Formatter::Options.new(compact_empty_hash: false)
      formatter = Formatter.new(source, [], options: options)
      SyntaxTree.parse(source).format(formatter)
      formatter.flush
      result = formatter.output.join

      # Should allow the hash to break across lines
      assert(result.include?("= {\n}"), "Expected empty hash to break across lines when plugin is disabled")
    end

    private

    def assert_format(expected, source = expected.chomp)
      options = Formatter::Options.new(compact_empty_hash: true)
      formatter = Formatter.new(source, [], options: options)
      SyntaxTree.parse(source).format(formatter)
      formatter.flush
      assert_equal(expected, formatter.output.join)
    end
  end
end
