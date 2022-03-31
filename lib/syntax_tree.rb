# frozen_string_literal: true

require "pp"
require "prettyprint"
require "ripper"
require "stringio"

require_relative "syntax_tree/node"
require_relative "syntax_tree/parser"
require_relative "syntax_tree/version"

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
  # A slightly enhanced PP that knows how to format recursively including
  # comments.
  class Formatter < PP
    COMMENT_PRIORITY = 1
    HEREDOC_PRIORITY = 2

    attr_reader :source, :stack, :quote

    def initialize(source, ...)
      super(...)

      @source = source
      @stack = []
      @quote = "\""
    end

    def format(node, stackable: true)
      stack << node if stackable
      doc = nil

      # If there are comments, then we're going to format them around the node
      # so that they get printed properly.
      if node.comments.any?
        leading, trailing = node.comments.partition(&:leading?)

        # Print all comments that were found before the node.
        leading.each do |comment|
          comment.format(self)
          breakable(force: true)
        end

        # If the node has a stree-ignore comment right before it, then we're
        # going to just print out the node as it was seen in the source.
        if leading.last&.ignore?
          doc = text(source[node.location.start_char...node.location.end_char])
        else
          doc = node.format(self)
        end

        # Print all comments that were found after the node.
        trailing.each do |comment|
          line_suffix(priority: COMMENT_PRIORITY) do
            text(" ")
            comment.format(self)
            break_parent
          end
        end
      else
        doc = node.format(self)
      end

      stack.pop if stackable
      doc
    end

    def format_each(nodes)
      nodes.each { |node| format(node) }
    end

    def parent
      stack[-2]
    end

    def parents
      stack[0...-1].reverse_each
    end
  end

  def self.parse(source)
    parser = Parser.new(source)
    response = parser.parse
    response unless parser.error?
  end

  def self.format(source)
    output = []

    formatter = Formatter.new(source, output)
    parse(source).format(formatter)

    formatter.flush
    output.join
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
