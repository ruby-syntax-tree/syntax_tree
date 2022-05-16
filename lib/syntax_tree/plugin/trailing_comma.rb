# frozen_string_literal: true

require "syntax_tree/formatter/trailing_comma"
SyntaxTree::Formatter.prepend(SyntaxTree::Formatter::TrailingComma)
