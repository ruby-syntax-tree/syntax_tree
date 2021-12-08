# frozen_string_literal: true

class SyntaxTree
  module CLI
    # An action of the CLI that prints out the AST for the given source.
    class AST
      def run(filepath, source)
        pp SyntaxTree.parse(source)
      end
    end

    # An action of the CLI that formats the source twice to check if the first
    # format is not idempotent.
    class Check
      def run(filepath, source)
        formatted = SyntaxTree.format(source)
        raise if formatted != SyntaxTree.format(formatted)
      end
    end

    # An action of the CLI that prints out the doc tree IR for the given source.
    class Doc
      def run(filepath, source)
        formatter = Formatter.new([])
        SyntaxTree.parse(source).format(formatter)
        pp formatter.groups.first
      end
    end

    # An action of the CLI that formats the input source and prints it out.
    class Format
      def run(filepath, source)
        puts SyntaxTree.format(source)
      end
    end

    # An action of the CLI that formats the input source and writes the
    # formatted output back to the file.
    class Write
      def run(filepath, source)
        File.write(filepath, SyntaxTree.format(source))
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
            errored |= run_for(action, filepath) if File.file?(filepath)
          end
        end
        
        errored ? 1 : 0
      end

      private

      def source_for(filepath)
        encoding =
          File.open(filepath, "r") do |file|
            header = file.readline
            header += file.readline if header.start_with?("#!")
            Ripper.new(header).tap(&:parse).encoding
          end

        File.read(filepath, encoding: encoding)
      end

      def run_for(action, filepath)
        action.run(filepath, source_for(filepath))
        false
      rescue => error
        warn("!!! Failed on #{filepath}")
        warn(error.message)
        warn(error.backtrace)
        true
      end
    end
  end
end
