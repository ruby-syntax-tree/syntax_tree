# frozen_string_literal: true

class SyntaxTree
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
      def run(filepath, source)
      end

      def success
      end

      def failure
      end
    end

    # An action of the CLI that prints out the AST for the given source.
    class AST < Action
      def run(filepath, source)
        pp SyntaxTree.parse(source)
      end
    end

    # An action of the CLI that ensures that the filepath is formatted as
    # expected.
    class Check < Action
      class UnformattedError < StandardError
      end

      def run(filepath, source)
        raise UnformattedError if source != SyntaxTree.format(source)
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

      def run(filepath, source)
        warning = "[#{Color.yellow("warn")}] #{filepath}"
        formatted = SyntaxTree.format(source)

        if formatted != SyntaxTree.format(formatted)
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
      def run(filepath, source)
        formatter = Formatter.new([])
        SyntaxTree.parse(source).format(formatter)
        pp formatter.groups.first
      end
    end

    # An action of the CLI that formats the input source and prints it out.
    class Format < Action
      def run(filepath, source)
        puts SyntaxTree.format(source)
      end
    end

    # An action of the CLI that formats the input source and writes the
    # formatted output back to the file.
    class Write < Action
      def run(filepath, source)
        print filepath
        start = Time.now

        formatted = SyntaxTree.format(source)
        File.write(filepath, formatted)

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
      stree MODE FILE

      MODE: ast | check | debug | doc | format | write
      FILE: one or more paths to files to parse
    HELP

    class << self
      # Run the CLI over the given array of strings that make up the arguments
      # passed to the invocation.
      def run(argv)
        if argv.length < 2
          warn(HELP)
          return 1
        end

        arg, *patterns = argv
        action =
          case arg
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

        errored = false
        patterns.each do |pattern|
          Dir.glob(pattern).each do |filepath|
            next unless File.file?(filepath)
            source = SyntaxTree.read(filepath)

            begin
              action.run(filepath, source)
            rescue ParseError => error
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
          end
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
