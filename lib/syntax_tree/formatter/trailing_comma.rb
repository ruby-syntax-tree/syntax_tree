# frozen_string_literal: true

module SyntaxTree
  class Formatter
    # This module overrides the trailing_comma? method on the formatter to
    # return true.
    module TrailingComma
      def trailing_comma?
        true
      end
    end
  end
end
