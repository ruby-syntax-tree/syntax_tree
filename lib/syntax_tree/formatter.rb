# frozen_string_literal: true

module SyntaxTree
  # A slightly enhanced PP that knows how to format recursively including
  # comments.
  class Formatter < PrettierPrint
    # We want to minimize as much as possible the number of options that are
    # available in syntax tree. For the most part, if users want non-default
    # formatting, they should override the format methods on the specific nodes
    # themselves. However, because of some history with prettier and the fact
    # that folks have become entrenched in their ways, we decided to provide a
    # small amount of configurability.
    #
    # Note that we're keeping this in a global-ish hash instead of just
    # overriding methods on classes so that other plugins can reference this if
    # necessary. For example, the RBS plugin references the quote style.
    OPTIONS = {
      quote: "\"",
      trailing_comma: false,
      target_ruby_version: Gem::Version.new(RUBY_VERSION)
    }

    COMMENT_PRIORITY = 1
    HEREDOC_PRIORITY = 2

    attr_reader :source, :stack

    # These options are overridden in plugins to we need to make sure they are
    # available here.
    attr_reader :quote, :trailing_comma, :target_ruby_version
    alias trailing_comma? trailing_comma

    def initialize(
      source,
      *args,
      quote: OPTIONS[:quote],
      trailing_comma: OPTIONS[:trailing_comma],
      target_ruby_version: OPTIONS[:target_ruby_version]
    )
      super(*args)

      @source = source
      @stack = []

      # Memoizing these values per formatter to make access faster.
      @quote = quote
      @trailing_comma = trailing_comma
      @target_ruby_version = target_ruby_version
    end

    def self.format(source, node)
      q = new(source, [])
      q.format(node)
      q.flush
      q.output.join
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
        doc =
          if leading.last&.ignore?
            range = source[node.location.start_char...node.location.end_char]
            separator = -> { breakable(indent: false, force: true) }
            seplist(range.split(/\r?\n/, -1), separator) { |line| text(line) }
          else
            node.format(self)
          end

        # Print all comments that were found after the node.
        trailing.each do |comment|
          line_suffix(priority: COMMENT_PRIORITY) do
            comment.inline? ? text(" ") : breakable
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
end
