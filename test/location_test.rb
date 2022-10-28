# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class LocationTest < Minitest::Test
    def test_lines
      location = Location.fixed(line: 1, char: 0, column: 0)
      location = location.to(Location.fixed(line: 3, char: 3, column: 3))

      assert_equal(1..3, location.lines)
    end

    def test_deconstruct
      location = Location.fixed(line: 1, char: 0, column: 0)

      assert_equal(1, location.start_line)
      assert_equal(0, location.start_char)
      assert_equal(0, location.start_column)
    end

    def test_deconstruct_keys
      location = Location.fixed(line: 1, char: 0, column: 0)

      assert_equal(1, location.start_line)
    end
  end
end
