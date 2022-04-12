# frozen_string_literal: true

module SyntaxTree
  module CLI
    # A utility wrapper around colored strings in the output.
    class Color
      attr_reader :value, :code

      def initialize(value, code)
        @value = value
        @code = code
      end

      def to_s
        "\033[#{code}m#{value}\033[0m"
      end

      def self.bold(value)
        new(value, "1")
      end

      def self.gray(value)
        new(value, "38;5;102")
      end

      def self.red(value)
        new(value, "1;31")
      end

      def self.yellow(value)
        new(value, "33")
      end
    end

    # The parent action class for the CLI that implements the basics.
    class Action
      def run(handler, filepath, source)
      end

      def success
      end

      def failure
      end
    end

    # An action of the CLI that prints out the AST for the given source.
    class AST < Action
      def run(handler, filepath, source)
        pp handler.parse(source)
      end
    end

    # An action of the CLI that ensures that the filepath is formatted as
    # expected.
    class Check < Action
      class UnformattedError < StandardError
      end

      def run(handler, filepath, source)
        raise UnformattedError if source != handler.format(source)
      rescue StandardError
        warn("[#{Color.yellow("warn")}] #{filepath}")
        raise
      end

      def success
        puts("All files matched expected format.")
      end

      def failure
        warn("The listed files did not match the expected format.")
      end
    end

    # An action of the CLI that formats the source twice to check if the first
    # format is not idempotent.
    class Debug < Action
      class NonIdempotentFormatError < StandardError
      end

      def run(handler, filepath, source)
        warning = "[#{Color.yellow("warn")}] #{filepath}"
        formatted = handler.format(source)

        if formatted != handler.format(formatted)
          raise NonIdempotentFormatError
        end
      rescue StandardError
        warn(warning)
        raise
      end

      def success
        puts("All files can be formatted idempotently.")
      end

      def failure
        warn("The listed files could not be formatted idempotently.")
      end
    end

    # An action of the CLI that prints out the doc tree IR for the given source.
    class Doc < Action
      def run(handler, filepath, source)
        formatter = Formatter.new([])
        handler.parse(source).format(formatter)
        pp formatter.groups.first
      end
    end

    # An action of the CLI that formats the input source and prints it out.
    class Format < Action
      def run(handler, filepath, source)
        puts handler.format(source)
      end
    end

    # An action of the CLI that formats the input source and writes the
    # formatted output back to the file.
    class Write < Action
      def run(handler, filepath, source)
        print filepath
        start = Time.now

        formatted = handler.format(source)
        File.write(filepath, formatted) if filepath != :stdin

        color = source == formatted ? Color.gray(filepath) : filepath
        delta = ((Time.now - start) * 1000).round

        puts "\r#{color} #{delta}ms"
      rescue StandardError
        puts "\r#{filepath}"
        raise
      end
    end

    # The help message displayed if the input arguments are not correctly
    # ordered or formatted.
    HELP = <<~HELP
      #{Color.bold("stree ast [OPTIONS] [FILE]")}
        Print out the AST corresponding to the given files

      #{Color.bold("stree check [OPTIONS] [FILE]")}
        Check that the given files are formatted as syntax tree would format them

      #{Color.bold("stree debug [OPTIONS] [FILE]")}
        Check that the given files can be formatted idempotently

      #{Color.bold("stree doc [OPTIONS] [FILE]")}
        Print out the doc tree that would be used to format the given files

      #{Color.bold("stree format [OPTIONS] [FILE]")}
        Print out the formatted version of the given files

      #{Color.bold("stree help")}
        Display this help message

      #{Color.bold("stree lsp")}
        Run syntax tree in language server mode

      #{Color.bold("stree version")}
        Output the current version of syntax tree

      #{Color.bold("stree write [OPTIONS] [FILE]")}
        Read, format, and write back the source of the given files

      [OPTIONS]

      --plugins=...
        A comma-separated list of plugins to load.
    HELP

    class << self
      # Run the CLI over the given array of strings that make up the arguments
      # passed to the invocation.
      def run(argv)
        name, *arguments = argv

        case name
        when "help"
          puts HELP
          return 0
        when "lsp"
          require "syntax_tree/language_server"
          LanguageServer.new.run
          return 0
        when "version"
          puts SyntaxTree::VERSION
          return 0
        end

        action =
          case name
          when "a", "ast"
            AST.new
          when "c", "check"
            Check.new
          when "debug"
            Debug.new
          when "doc"
            Doc.new
          when "f", "format"
            Format.new
          when "w", "write"
            Write.new
          else
            warn(HELP)
            return 1
          end

        # If we're not reading from stdin and the user didn't supply and
        # filepaths to be read, then we exit with the usage message.
        if STDIN.tty? && arguments.empty?
          warn(HELP)
          return 1
        end

        # If there are any plugins specified on the command line, then load them
        # by requiring them here. We do this by transforming something like
        #
        #     stree format --plugins=haml template.haml
        #
        # into
        #
        #     require "syntax_tree/haml"
        #
        if arguments.first&.start_with?("--plugins=")
          plugins = arguments.shift[/^--plugins=(.*)$/, 1]
          plugins.split(",").each { |plugin| require "syntax_tree/#{plugin}" }
        end

        # Track whether or not there are any errors from any of the files that
        # we take action on so that we can properly clean up and exit.
        errored = false

        each_file(arguments) do |handler, filepath, source|
          action.run(handler, filepath, source)
        rescue Parser::ParseError => error
          warn("Error: #{error.message}")

          if error.lineno
            highlight_error(error, source)
          else
            warn(error.message)
            warn(error.backtrace)
          end

          errored = true
        rescue Check::UnformattedError, Debug::NonIdempotentFormatError
          errored = true
        rescue => error
          warn(error.message)
          warn(error.backtrace)
          errored = true
        end

        if errored
          action.failure
          1
        else
          action.success
          0
        end
      end

      private

      def each_file(arguments)
        if STDIN.tty?
          arguments.each do |pattern|
            Dir.glob(pattern).each do |filepath|
              next unless File.file?(filepath)

              handler = HANDLERS[File.extname(filepath)]
              source = handler.read(filepath)
              yield handler, filepath, source
            end
          end
        else
          yield HANDLERS[".rb"], :stdin, STDIN.read
        end
      end

      # Highlights a snippet from a source and parse error.
      def highlight_error(error, source)
        lines = source.lines

        maximum = [error.lineno + 3, lines.length].min
        digits = Math.log10(maximum).ceil

        ([error.lineno - 3, 0].max...maximum).each do |line_index|
          line_number = line_index + 1

          if line_number == error.lineno
            part1 = Color.red(">")
            part2 = Color.gray("%#{digits}d |" % line_number)
            warn("#{part1} #{part2} #{colorize_line(lines[line_index])}")

            part3 = Color.gray("  %#{digits}s |" % " ")
            warn("#{part3} #{" " * error.column}#{Color.red("^")}")
          else
            prefix = Color.gray("  %#{digits}d |" % line_number)
            warn("#{prefix} #{colorize_line(lines[line_index])}")
          end
        end
      end

      # Take a line of Ruby source and colorize the output.
      def colorize_line(line)
        require "irb"
        IRB::Color.colorize_code(line, complete: false, ignore_error: true)
      end
    end
  end
end
