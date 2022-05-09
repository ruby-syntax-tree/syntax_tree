# frozen_string_literal: true

require "syntax_tree/formatter/single_quotes"
SyntaxTree::Formatter.prepend(SyntaxTree::Formatter::SingleQuotes)
