# frozen_string_literal: true

require "thread"
require "syntax_tree/format"

# Syntax Tree is a formatter built on top of the internal CRuby parser.
module SyntaxTree
  autoload :CLI, "syntax_tree/cli"
  autoload :LSP, "syntax_tree/lsp"
  autoload :Rake, "syntax_tree/rake"
  autoload :Version, "syntax_tree/version"

  # Raised when an error is encountered while parsing the source to be
  # formatted through the #format or #format_file methods.
  class ParseError < StandardError
  end

  # We want to minimize as much as possible the number of options that are
  # available in the formatter. For the most part, if users want non-default
  # formatting, they should override the visit methods below. However, because
  # of some history with prettier and the fact that folks have become entrenched
  # in their ways, we decided to provide a small amount of configurability.
  class Options
    # The print width is the suggested line length that should be used when
    # formatting the source. Note that this is not a hard limit like a linter.
    # Instead, it is used as a guideline for how long lines _should_ be. For
    # example, if you have the following code:
    #
    #     foo do
    #       bar
    #     end
    #
    # In this case, the formatter will see that the block fits into the print
    # width and will rewrite it using the `{}` syntax. This will actually make
    # the line longer than originally written. This is why it is helpful to
    # think of it as a suggestion, rather than a limit.
    attr_accessor :print_width

    # The quote style to use when formatting string literals. This can be
    # either a single quote (`'`) or a double quote (`"`). This is a
    # preference, but not a hard rule. If a string contains interpolation,
    # the formatter will leave it as it is in the source to avoid changing the
    # meaning of the code.
    attr_accessor :preferred_quote

    # Trailing commas can be used in multi-line collection literals and when
    # specifying arguments to a method call, in most cases (there are a few
    # rare exceptions). This option controls whether or not they should be
    # used.
    attr_accessor :trailing_comma

    def initialize(print_width: 100, preferred_quote: '"', trailing_comma: false)
      @print_width = print_width
      @preferred_quote = preferred_quote
      @trailing_comma = trailing_comma
    end
  end

  # Mutex to synchronize modifications to the module configuration.
  @lock = Mutex.new

  # The default formatting options used by the formatter when an options object
  # is not explicitly provided.
  @options = Options.new.freeze

  # Configure the default formatting options that will be used when options are
  # not explicitly provided.
  def self.configure
    @lock.synchronize do
      options = @options.dup
      yield options
      @options = options.freeze
    end
  end

  # Create a new set of options that falls back to the default options for any
  # unspecified values.
  def self.options(print_width: :default, preferred_quote: :default, trailing_comma: :default)
    options = @lock.synchronize { @options.dup }
    options.print_width = print_width unless print_width == :default
    options.preferred_quote = preferred_quote unless preferred_quote == :default
    options.trailing_comma = trailing_comma unless trailing_comma == :default
    options.freeze
  end

  # Options should not be directly used by consumers. Instead they should create
  # new options object through the SyntaxTree.options method.
  private_constant :Options

  # It is possible to extend the formatter to support other languages by
  # registering extension. An extension is any object that responds to both
  # the #format and #format_file methods.
  @handlers = Hash.new(SyntaxTree)

  # This is a hook provided so that plugins can register themselves as the
  # handler for a particular file type.
  def self.register_handler(extension, handler)
    @lock.synchronize { @handlers[extension] = handler }
  end

  # Unregisters the handler for the given file extension.
  def self.unregister_handler(extension)
    @lock.synchronize { @handlers.delete(extension) }
  end

  # Retrieves the handler registered for the given file extension.
  def self.handler_for(extension)
    @lock.synchronize { @handlers[extension] }
  end

  class << self
    # Parses the given source and returns the formatted source.
    def format(source, options = @options)
      process(Prism.parse(source), options)
    end

    # Parses the given file and returns the formatted source.
    def format_file(filepath, options = @options)
      process(Prism.parse_file(filepath), options)
    end

    private

    # Processes the result of parsing the source and returns the formatted
    # source.
    def process(result, options)
      raise ParseError, result.errors_format if result.failure?
      result.attach_comments!

      formatter = Prism::Format.new(result.source.source, options)
      result.value.accept(formatter)

      if (data_loc = result.data_loc)
        formatted = formatter.format
        formatted.empty? ? data_loc.slice : "#{formatted}\n\n#{data_loc.slice}"
      else
        "#{formatter.format}\n"
      end
    end
  end
end
