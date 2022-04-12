# frozen_string_literal: true

require "json"
require "pp"
require "prettyprint"
require "ripper"
require "stringio"

require_relative "syntax_tree/formatter"
require_relative "syntax_tree/node"
require_relative "syntax_tree/parser"
require_relative "syntax_tree/version"
require_relative "syntax_tree/visitor"
require_relative "syntax_tree/visitor/json_visitor"
require_relative "syntax_tree/visitor/pretty_print_visitor"

# If PrettyPrint::Align isn't defined, then we haven't gotten the updated
# version of prettyprint. In that case we'll define our own. This is going to
# overwrite a bunch of methods, so silencing them as well.
unless PrettyPrint.const_defined?(:Align)
  verbose = $VERBOSE
  $VERBOSE = nil

  begin
    require_relative "syntax_tree/prettyprint"
  ensure
    $VERBOSE = verbose
  end
end

module SyntaxTree
  # This holds references to objects that respond to both #parse and #format
  # so that we can use them in the CLI.
  HANDLERS = {}
  HANDLERS.default = SyntaxTree

  # This is a hook provided so that plugins can register themselves as the
  # handler for a particular file type.
  def self.register_handler(extension, handler)
    HANDLERS[extension] = handler
  end

  # Parses the given source and returns the syntax tree.
  def self.parse(source)
    parser = Parser.new(source)
    response = parser.parse
    response unless parser.error?
  end

  # Parses the given source and returns the formatted source.
  def self.format(source)
    formatter = Formatter.new(source, [])
    parse(source).format(formatter)

    formatter.flush
    formatter.output.join
  end

  # Returns the source from the given filepath taking into account any potential
  # magic encoding comments.
  def self.read(filepath)
    encoding =
      File.open(filepath, "r") do |file|
        header = file.readline
        header += file.readline if header.start_with?("#!")
        Ripper.new(header).tap(&:parse).encoding
      end

    File.read(filepath, encoding: encoding)
  end
end
