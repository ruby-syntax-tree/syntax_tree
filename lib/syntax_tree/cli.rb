# frozen_string_literal: true

require "etc"
require "optparse"

module SyntaxTree
  # Syntax Tree ships with the `stree` CLI, which can be used to inspect and
  # manipulate Ruby code. This module is responsible for powering that CLI.
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

    # An item of work that corresponds to a file to be processed.
    class FileItem
      attr_reader :filepath

      def initialize(filepath)
        @filepath = filepath
      end

      def handler
        HANDLERS[File.extname(filepath)]
      end

      def source
        handler.read(filepath)
      end

      def writable?
        File.writable?(filepath)
      end
    end

    # An item of work that corresponds to a script content passed via the
    # command line.
    class ScriptItem
      attr_reader :source

      def initialize(source)
        @source = source
      end

      def handler
        HANDLERS[".rb"]
      end

      def filepath
        :script
      end

      def writable?
        false
      end
    end

    # An item of work that correspond to the content passed in via stdin.
    class STDINItem
      def handler
        HANDLERS[".rb"]
      end

      def filepath
        :stdin
      end

      def source
        $stdin.read
      end

      def writable?
        false
      end
    end

    # The parent action class for the CLI that implements the basics.
    class Action
      attr_reader :options

      def initialize(options)
        @options = options
      end

      def run(item)
      end

      def success
      end

      def failure
      end
    end

    # An action of the CLI that prints out the AST for the given source.
    class AST < Action
      def run(item)
        pp item.handler.parse(item.source)
      end
    end

    # An action of the CLI that ensures that the filepath is formatted as
    # expected.
    class Check < Action
      class UnformattedError < StandardError
      end

      def run(item)
        source = item.source
        formatted =
          item.handler.format(
            source,
            options.print_width,
            options: options.formatter_options
          )

        raise UnformattedError if source != formatted
      rescue StandardError
        warn("[#{Color.yellow("warn")}] #{item.filepath}")
        raise
      end

      def success
        puts("All files matched expected format.")
      end

      def failure
        warn("The listed files did not match the expected format.")
      end
    end

    # An action of the CLI that generates ctags for the given source.
    class CTags < Action
      attr_reader :entries

      def initialize(options)
        super(options)
        @entries = []
      end

      def run(item)
        lines = item.source.lines(chomp: true)

        SyntaxTree
          .index(item.source)
          .each do |entry|
            line = lines[entry.location.line - 1]
            pattern = "/^#{line.gsub("\\", "\\\\\\\\").gsub("/", "\\/")}$/;\""

            entries << case entry
            when SyntaxTree::Index::ModuleDefinition
              parts = [entry.name, item.filepath, pattern, "m"]

              if entry.nesting != [[entry.name]]
                parts << "class:#{entry.nesting.flatten.tap(&:pop).join(".")}"
              end

              parts.join("\t")
            when SyntaxTree::Index::ClassDefinition
              parts = [entry.name, item.filepath, pattern, "c"]

              if entry.nesting != [[entry.name]]
                parts << "class:#{entry.nesting.flatten.tap(&:pop).join(".")}"
              end

              unless entry.superclass.empty?
                inherits = entry.superclass.join(".").delete_prefix(".")
                parts << "inherits:#{inherits}"
              end

              parts.join("\t")
            when SyntaxTree::Index::MethodDefinition
              parts = [entry.name, item.filepath, pattern, "f"]

              unless entry.nesting.empty?
                parts << "class:#{entry.nesting.flatten.join(".")}"
              end

              parts.join("\t")
            when SyntaxTree::Index::SingletonMethodDefinition
              parts = [entry.name, item.filepath, pattern, "F"]

              unless entry.nesting.empty?
                parts << "class:#{entry.nesting.flatten.join(".")}"
              end

              parts.join("\t")
            when SyntaxTree::Index::AliasMethodDefinition
              parts = [entry.name, item.filepath, pattern, "a"]

              unless entry.nesting.empty?
                parts << "class:#{entry.nesting.flatten.join(".")}"
              end

              parts.join("\t")
            when SyntaxTree::Index::ConstantDefinition
              parts = [entry.name, item.filepath, pattern, "C"]

              unless entry.nesting.empty?
                parts << "class:#{entry.nesting.flatten.join(".")}"
              end

              parts.join("\t")
            end
          end
      end

      def success
        puts(<<~HEADER)
          !_TAG_FILE_FORMAT	2	/extended format; --format=1 will not append ;" to lines/
          !_TAG_FILE_SORTED	1	/0=unsorted, 1=sorted, 2=foldcase/
        HEADER

        entries.sort.each { |entry| puts(entry) }
      end
    end

    # An action of the CLI that formats the source twice to check if the first
    # format is not idempotent.
    class Debug < Action
      class NonIdempotentFormatError < StandardError
      end

      def run(item)
        handler = item.handler
        warning = "[#{Color.yellow("warn")}] #{item.filepath}"

        formatted =
          handler.format(
            item.source,
            options.print_width,
            options: options.formatter_options
          )

        double_formatted =
          handler.format(
            formatted,
            options.print_width,
            options: options.formatter_options
          )

        raise NonIdempotentFormatError if formatted != double_formatted
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
      def run(item)
        source = item.source

        formatter_options = options.formatter_options
        formatter = Formatter.new(source, [], options: formatter_options)

        item.handler.parse(source).format(formatter)
        pp formatter.groups.first
      end
    end

    # An action of the CLI that outputs a pattern-matching Ruby expression that
    # would match the first expression of the input given.
    class Expr < Action
      def run(item)
        program = item.handler.parse(item.source)

        if (expressions = program.statements.body) && expressions.size == 1
          puts expressions.first.construct_keys
        else
          warn("The input to `stree expr` must be a single expression.")
          exit(1)
        end
      end
    end

    # An action of the CLI that formats the input source and prints it out.
    class Format < Action
      def run(item)
        formatted =
          item.handler.format(
            item.source,
            options.print_width,
            options: options.formatter_options
          )

        puts formatted
      end
    end

    # An action of the CLI that converts the source into its equivalent JSON
    # representation.
    class Json < Action
      def run(item)
        object = item.handler.parse(item.source).accept(JSONVisitor.new)
        puts JSON.pretty_generate(object)
      end
    end

    # An action of the CLI that outputs a pattern-matching Ruby expression that
    # would match the input given.
    class Match < Action
      def run(item)
        puts item.handler.parse(item.source).construct_keys
      end
    end

    # An action of the CLI that searches for the given pattern matching pattern
    # in the given files.
    class Search < Action
      attr_reader :search

      def initialize(query)
        query = File.read(query) if File.readable?(query)
        pattern =
          begin
            Pattern.new(query).compile
          rescue Pattern::CompilationError => error
            warn(error.message)
            exit(1)
          end

        @search = SyntaxTree::Search.new(pattern)
      end

      def run(item)
        search.scan(item.handler.parse(item.source)) do |node|
          location = node.location
          line = location.start_line

          bold_range =
            if line == location.end_line
              location.start_column...location.end_column
            else
              location.start_column..
            end

          source = item.source.lines[line - 1].chomp
          source[bold_range] = Color.bold(source[bold_range]).to_s

          puts("#{item.filepath}:#{line}:#{location.start_column}: #{source}")
        end
      end
    end

    # An action of the CLI that formats the input source and writes the
    # formatted output back to the file.
    class Write < Action
      def run(item)
        filepath = item.filepath
        start = Time.now

        source = item.source
        formatted =
          item.handler.format(
            source,
            options.print_width,
            options: options.formatter_options
          )
        changed = source != formatted

        File.write(filepath, formatted) if item.writable? && changed

        color = changed ? filepath : Color.gray(filepath)
        delta = ((Time.now - start) * 1000).round

        puts "#{color} #{delta}ms"
      rescue StandardError
        puts filepath
        raise
      end
    end

    # The help message displayed if the input arguments are not correctly
    # ordered or formatted.
    HELP = <<~HELP
      #{Color.bold("stree ast [--plugins=...] [--print-width=NUMBER] [-e SCRIPT] FILE")}
        Print out the AST corresponding to the given files

      #{Color.bold("stree check [--plugins=...] [--print-width=NUMBER] [-e SCRIPT] FILE")}
        Check that the given files are formatted as syntax tree would format them

      #{Color.bold("stree ctags [-e SCRIPT] FILE")}
        Print out a ctags-compatible index of the given files

      #{Color.bold("stree debug [--plugins=...] [--print-width=NUMBER] [-e SCRIPT] FILE")}
        Check that the given files can be formatted idempotently

      #{Color.bold("stree doc [--plugins=...] [-e SCRIPT] FILE")}
        Print out the doc tree that would be used to format the given files

      #{Color.bold("stree expr [-e SCRIPT] FILE")}
        Print out a pattern-matching Ruby expression that would match the first
        expression of the given files

      #{Color.bold("stree format [--plugins=...] [--print-width=NUMBER] [-e SCRIPT] FILE")}
        Print out the formatted version of the given files

      #{Color.bold("stree json [--plugins=...] [-e SCRIPT] FILE")}
        Print out the JSON representation of the given files

      #{Color.bold("stree match [--plugins=...] [-e SCRIPT] FILE")}
        Print out a pattern-matching Ruby expression that would match the given files

      #{Color.bold("stree help")}
        Display this help message

      #{Color.bold("stree lsp [--plugins=...] [--print-width=NUMBER]")}
        Run syntax tree in language server mode

      #{Color.bold("stree search PATTERN [-e SCRIPT] FILE")}
        Search for the given pattern in the given files

      #{Color.bold("stree version")}
        Output the current version of syntax tree

      #{Color.bold("stree write [--plugins=...] [--print-width=NUMBER] [-e SCRIPT] FILE")}
        Read, format, and write back the source of the given files

      --plugins=...
        A comma-separated list of plugins to load.

      --print-width=NUMBER
        The maximum line width to use when formatting.

      -e SCRIPT
        Parse an inline Ruby string.
    HELP

    # This represents all of the options that can be passed to the CLI. It is
    # responsible for parsing the list and then returning the file paths at the
    # end.
    class Options
      attr_reader :ignore_files,
                  :plugins,
                  :print_width,
                  :scripts,
                  :target_ruby_version

      def initialize
        @ignore_files = []
        @plugins = []
        @print_width = DEFAULT_PRINT_WIDTH
        @scripts = []
        @target_ruby_version = DEFAULT_RUBY_VERSION
      end

      def formatter_options
        @formatter_options ||=
          Formatter::Options.new(target_ruby_version: target_ruby_version)
      end

      def parse(arguments)
        parser.parse!(arguments)
      end

      private

      def parser
        OptionParser.new do |opts|
          # If there is a glob specified to ignore, then we'll track that here.
          # Any of the CLI commands that operate on filenames will then ignore
          # this set of files.
          opts.on("--ignore-files=GLOB") do |glob|
            @ignore_files << (glob.match(/\A'(.*)'\z/) ? $1 : glob)
          end

          # If there are any plugins specified on the command line, then load
          # them by requiring them here. We do this by transforming something
          # like
          #
          #     stree format --plugins=haml template.haml
          #
          # into
          #
          #     require "syntax_tree/haml"
          #
          opts.on("--plugins=PLUGINS") do |plugins|
            @plugins = plugins.split(",")
            @plugins.each { |plugin| require "syntax_tree/#{plugin}" }
          end

          # If there is a print width specified on the command line, then
          # parse that out here and use it when formatting.
          opts.on("--print-width=NUMBER", Integer) do |print_width|
            @print_width = print_width
          end

          # If there is a script specified on the command line, then parse
          # it and add it to the list of scripts to run.
          opts.on("-e SCRIPT") { |script| @scripts << script }

          # If there is a target ruby version specified on the command line,
          # parse that out and use it when formatting.
          opts.on("--target-ruby-version=VERSION") do |version|
            @target_ruby_version = Formatter::SemanticVersion.new(version)
          end
        end
      end
    end

    # We allow a minimal configuration file to act as additional command line
    # arguments to the CLI. Each line of the config file should be a new
    # argument, as in:
    #
    #     --plugins=plugin/single_quote
    #     --print-width=100
    #
    # When invoking the CLI, we will read this config file and then parse it if
    # it exists in the current working directory.
    class ConfigFile
      FILENAME = ".streerc"

      attr_reader :filepath

      def initialize
        @filepath = File.join(Dir.pwd, FILENAME)
      end

      def exists?
        File.readable?(filepath)
      end

      def arguments
        exists? ? File.readlines(filepath, chomp: true) : []
      end
    end

    class << self
      # Run the CLI over the given array of strings that make up the arguments
      # passed to the invocation.
      def run(argv)
        name, *arguments = argv

        config_file = ConfigFile.new
        arguments.unshift(*config_file.arguments)

        options = Options.new
        options.parse(arguments)

        action =
          case name
          when "a", "ast"
            AST.new(options)
          when "c", "check"
            Check.new(options)
          when "ctags"
            CTags.new(options)
          when "debug"
            Debug.new(options)
          when "doc"
            Doc.new(options)
          when "e", "expr"
            Expr.new(options)
          when "f", "format"
            Format.new(options)
          when "help"
            puts HELP
            return 0
          when "j", "json"
            Json.new(options)
          when "lsp"
            LanguageServer.new(print_width: options.print_width).run
            return 0
          when "m", "match"
            Match.new(options)
          when "s", "search"
            Search.new(arguments.shift)
          when "version"
            puts SyntaxTree::VERSION
            return 0
          when "w", "write"
            Write.new(options)
          else
            warn(HELP)
            return 1
          end

        # We're going to build up a queue of items to process.
        queue = Queue.new

        # If there are any arguments or scripts, then we'll add those to the
        # queue. Otherwise we'll read the content off STDIN.
        if arguments.any? || options.scripts.any?
          arguments.each do |pattern|
            Dir
              .glob(pattern)
              .each do |filepath|
                # Skip past invalid filepaths by default.
                next unless File.readable?(filepath)

                # Skip past any ignored filepaths.
                next if options.ignore_files.any? { File.fnmatch(_1, filepath) }

                # Otherwise, a new file item for the given filepath to the list.
                queue << FileItem.new(filepath)
              end
          end

          options.scripts.each { |script| queue << ScriptItem.new(script) }
        else
          queue << STDINItem.new
        end

        # At the end, we're going to return whether or not this worker ever
        # encountered an error.
        if process_queue(queue, action)
          action.failure
          1
        else
          action.success
          0
        end
      end

      private

      # Processes each item in the queue with the given action. Returns whether
      # or not any errors were encountered.
      def process_queue(queue, action)
        workers =
          [Etc.nprocessors, queue.size].min.times.map do
            Thread.new do
              # Propagate errors in the worker threads up to the parent thread.
              Thread.current.abort_on_exception = true

              # Track whether or not there are any errors from any of the files
              # that we take action on so that we can properly clean up and
              # exit.
              errored = false

              # While there is still work left to do, shift off the queue and
              # process the item.
              until queue.empty?
                item = queue.shift
                errored |=
                  begin
                    action.run(item)
                    false
                  rescue Parser::ParseError => error
                    warn("Error: #{error.message}")
                    highlight_error(error, item.source)
                    true
                  rescue Check::UnformattedError,
                         Debug::NonIdempotentFormatError
                    true
                  rescue StandardError => error
                    warn(error.message)
                    warn(error.backtrace)
                    true
                  end
              end

              # At the end, we're going to return whether or not this worker
              # ever encountered an error.
              errored
            end
          end

        workers.map(&:value).inject(:|)
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
        IRB::Color.colorize_code(line, **colorize_options)
      end

      # These are the options we're going to pass into IRB::Color.colorize_code.
      # Since we support multiple versions of IRB, we're going to need to do
      # some reflection to make sure we always pass valid options.
      def colorize_options
        options = { complete: false }

        parameters = IRB::Color.method(:colorize_code).parameters
        if parameters.any? { |(_type, name)| name == :ignore_error }
          options[:ignore_error] = true
        end

        options
      end
    end
  end
end
