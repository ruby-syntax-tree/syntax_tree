# frozen_string_literal: true

require "prettier_print"
require "ripper"

require_relative "syntax_tree/formatter"
require_relative "syntax_tree/node"
require_relative "syntax_tree/parser"
require_relative "syntax_tree/version"

# Syntax Tree is a suite of tools built on top of the internal CRuby parser. It
# provides the ability to generate a syntax tree from source, as well as the
# tools necessary to inspect and manipulate that syntax tree. It can be used to
# build formatters, linters, language servers, and more.
module SyntaxTree
  autoload :LanguageServer, "syntax_tree/language_server"

  # This holds references to objects that respond to both #parse and #format
  # so that we can use them in the CLI.
  HANDLERS = {}
  HANDLERS.default = SyntaxTree

  # This is the default print width when formatting. It can be overridden in the
  # CLI by passing the --print-width option or here in the API by passing the
  # optional second argument to ::format.
  DEFAULT_PRINT_WIDTH = 80

  # This is the default ruby version that we're going to target for formatting.
  # It shouldn't really be changed except in very niche circumstances.
  DEFAULT_RUBY_VERSION = Formatter::SemanticVersion.new(RUBY_VERSION).freeze

  # The default indentation level for formatting. We allow changing this so
  # that Syntax Tree can format arbitrary parts of a document.
  DEFAULT_INDENTATION = 0

  # Parses the given source and returns the formatted source.
  def self.format(
    source,
    maxwidth = DEFAULT_PRINT_WIDTH,
    base_indentation = DEFAULT_INDENTATION,
    options: Formatter::Options.new
  )
    format_node(
      source,
      parse(source),
      maxwidth,
      base_indentation,
      options: options
    )
  end

  # Parses the given file and returns the formatted source.
  def self.format_file(
    filepath,
    maxwidth = DEFAULT_PRINT_WIDTH,
    base_indentation = DEFAULT_INDENTATION,
    options: Formatter::Options.new
  )
    format(read(filepath), maxwidth, base_indentation, options: options)
  end

  # Accepts a node in the tree and returns the formatted source.
  def self.format_node(
    source,
    node,
    maxwidth = DEFAULT_PRINT_WIDTH,
    base_indentation = DEFAULT_INDENTATION,
    options: Formatter::Options.new
  )
    formatter = Formatter.new(source, [], maxwidth, options: options)
    node.format(formatter)

    formatter.flush(base_indentation)
    formatter.output.join
  end

  # Parses the given source and returns the syntax tree.
  def self.parse(source)
    parser = Parser.new(source)
    response = parser.parse
    response unless parser.error?
  end

  # Returns the source from the given filepath taking into account any potential
  # magic encoding comments.
  def self.read(filepath)
    encoding =
      File.open(filepath, "r") do |file|
        break Encoding.default_external if file.eof?

        header = file.readline
        header += file.readline if !file.eof? && header.start_with?("#!")
        Ripper.new(header).tap(&:parse).encoding
      end

    File.read(filepath, encoding: encoding)
  end

  # This is a hook provided so that plugins can register themselves as the
  # handler for a particular file type.
  def self.register_handler(extension, handler)
    HANDLERS[extension] = handler
  end
end
