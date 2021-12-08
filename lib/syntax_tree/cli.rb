# frozen_string_literal: true

class SyntaxTree
  module CLI
    # A utility wrapper around colored strings in the output.
    class ColoredString
      COLORS = { default: "0", gray: "38;5;102", yellow: "33" }

      attr_reader :code, :string

      def initialize(color, string)
        @code = COLORS[color]
        @string = string
      end

      def to_s
        "\033[#{code}m#{string}\033[0m"
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

    # An action of the CLI that formats the source twice to check if the first
    # format is not idempotent.
    class Check < Action
      def run(filepath, source)
        formatted = SyntaxTree.format(source)
        return true if formatted == SyntaxTree.format(formatted)

        puts "[#{ColoredString.new(:yellow, "warn")}] #{filepath}"
        false
      end

      def success
        puts "All files matched expected format."
      end

      def failure
        warn("The listed files did not match the expected format.")
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

        delta = ((Time.now - start) * 1000).round
        color = source == formatted ? :gray : :default

        puts "\r#{ColoredString.new(color, filepath)} #{delta}ms"
      end
    end

    # The help message displayed if the input arguments are not correctly
    # ordered or formatted.
    HELP = <<~HELP
      stree MODE FILE

      MODE: ast | check | doc | format | write
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
          when "d", "doc"
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

            begin
              action.run(filepath, source_for(filepath))
            rescue => error
              warn("!!! Failed on #{filepath}")
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

      # Returns the source from the given filepath taking into account any
      # potential magic encoding comments.
      def source_for(filepath)
        encoding =
          File.open(filepath, "r") do |file|
            header = file.readline
            header += file.readline if header.start_with?("#!")
            Ripper.new(header).tap(&:parse).encoding
          end

        File.read(filepath, encoding: encoding)
      end
    end
  end
end
