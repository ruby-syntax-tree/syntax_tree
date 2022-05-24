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

      case location
      in [1, 0, 0, *]
      end
    end

    def test_deconstruct_keys
      location = Location.fixed(line: 1, char: 0, column: 0)

      case location
      in { start_line: 1 }
      end
    end
  end
end
