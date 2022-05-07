# frozen_string_literal: true

module SyntaxTree
  class Formatter
    # This module overrides the quote method on the formatter to use single
    # quotes for everything instead of double quotes.
    module SingleQuotes
      def quote
        "'"
      end
    end
  end
end
