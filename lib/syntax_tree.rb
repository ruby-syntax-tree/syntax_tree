# frozen_string_literal: true

require "prettier_print"
require "pp"
require "ripper"

require_relative "syntax_tree/node"
require_relative "syntax_tree/basic_visitor"
require_relative "syntax_tree/visitor"

require_relative "syntax_tree/formatter"
require_relative "syntax_tree/parser"
require_relative "syntax_tree/version"

# Syntax Tree is a suite of tools built on top of the internal CRuby parser. It
# provides the ability to generate a syntax tree from source, as well as the
# tools necessary to inspect and manipulate that syntax tree. It can be used to
# build formatters, linters, language servers, and more.
module SyntaxTree
  # Syntax Tree the library has many features that aren't always used by the
  # CLI. Requiring those features takes time, so we autoload as many constants
  # as possible in order to keep the CLI as fast as possible.

  autoload :Database, "syntax_tree/database"
  autoload :DSL, "syntax_tree/dsl"
  autoload :FieldVisitor, "syntax_tree/field_visitor"
  autoload :Index, "syntax_tree/index"
  autoload :JSONVisitor, "syntax_tree/json_visitor"
  autoload :LanguageServer, "syntax_tree/language_server"
  autoload :MatchVisitor, "syntax_tree/match_visitor"
  autoload :Mermaid, "syntax_tree/mermaid"
  autoload :MermaidVisitor, "syntax_tree/mermaid_visitor"
  autoload :MutationVisitor, "syntax_tree/mutation_visitor"
  autoload :Pattern, "syntax_tree/pattern"
  autoload :PrettyPrintVisitor, "syntax_tree/pretty_print_visitor"
  autoload :Search, "syntax_tree/search"
  autoload :Translation, "syntax_tree/translation"
  autoload :WithScope, "syntax_tree/with_scope"
  autoload :YARV, "syntax_tree/yarv"

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

  # Indexes the given source code to return a list of all class, module, and
  # method definitions. Used to quickly provide indexing capability for IDEs or
  # documentation generation.
  def self.index(source)
    Index.index(source)
  end

  # Indexes the given file to return a list of all class, module, and method
  # definitions. Used to quickly provide indexing capability for IDEs or
  # documentation generation.
  def self.index_file(filepath)
    Index.index_file(filepath)
  end

  # A convenience method for creating a new mutation visitor.
  def self.mutation
    visitor = MutationVisitor.new
    yield visitor
    visitor
  end

  # Parses the given source and returns the syntax tree.
  def self.parse(source)
    parser = Parser.new(source)
    response = parser.parse
    response unless parser.error?
  end

  # Parses the given file and returns the syntax tree.
  def self.parse_file(filepath)
    parse(read(filepath))
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

  # Searches through the given source using the given pattern and yields each
  # node in the tree that matches the pattern to the given block.
  def self.search(source, query, &block)
    pattern = Pattern.new(query).compile
    program = parse(source)

    Search.new(pattern).scan(program, &block)
  end

  # Searches through the given file using the given pattern and yields each
  # node in the tree that matches the pattern to the given block.
  def self.search_file(filepath, query, &block)
    search(read(filepath), query, &block)
  end
end
