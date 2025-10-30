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

      def self.yellow(value)
        new(value, "33")
      end
    end

    # An item of work that corresponds to a file to be processed.
    class FileItem
      def initialize(filepath)
        @filepath = filepath
      end

      def handler
        SyntaxTree.handler_for(File.extname(filepath))
      end

      attr_reader :filepath

      def source
        File.read(filepath)
      end

      def writable?
        File.writable?(filepath)
      end
    end

    # An item of work that corresponds to a script content passed via the
    # command line.
    class ScriptItem
      def initialize(source, extension)
        @source = source
        @extension = extension
      end

      def handler
        SyntaxTree.handler_for(@extension)
      end

      def filepath
        :script
      end

      attr_reader :source

      def writable?
        false
      end
    end

    # An item of work that correspond to the content passed in via stdin.
    class STDINItem
      def initialize(extension)
        @extension = extension
      end

      def handler
        SyntaxTree.handler_for(@extension)
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

    # An action of the CLI that ensures that the filepath is formatted as
    # expected.
    class Check < Action
      class UnformattedError < StandardError
      end

      def run(item)
        source = item.source
        formatted = item.handler.format(source, options)
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

    # An action of the CLI that formats the source twice to check if the first
    # format is not idempotent.
    class Debug < Action
      class NonIdempotentFormatError < StandardError
      end

      def run(item)
        handler = item.handler
        formatted = handler.format(item.source, options)
        double_formatted = handler.format(formatted, options)
        raise NonIdempotentFormatError if formatted != double_formatted
      rescue StandardError
        warn("[#{Color.yellow("warn")}] #{item.filepath}")
        raise
      end

      def success
        puts("All files can be formatted idempotently.")
      end

      def failure
        warn("The listed files could not be formatted idempotently.")
      end
    end

    # An action of the CLI that formats the input source and prints it out.
    class Format < Action
      def run(item)
        puts item.handler.format(item.source, options)
      end
    end

    # An action of the CLI that formats the input source and writes the
    # formatted output back to the file.
    class Write < Action
      def run(item)
        filepath = item.filepath
        start = Time.now

        source = item.source
        formatted = item.handler.format(source, options)
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
      #{Color.bold("stree check OPTIONS? SOURCE")}
        Check that the given files are formatted as syntax tree would format them

      #{Color.bold("stree debug OPTIONS? SOURCE")}
        Check that the given files can be formatted idempotently

      #{Color.bold("stree format OPTIONS? SOURCE")}
        Print out the formatted version of the given files

      #{Color.bold("stree help")}
        Display this help message

      #{Color.bold("stree lsp OPTIONS?")}
        Run syntax tree in language server mode

      #{Color.bold("stree version")}
        Output the current version of syntax tree

      #{Color.bold("stree write OPTIONS? SOURCE")}
        Read, format, and write back the source of the given files

      OPTIONS:

      --config=...
        Path to a configuration file. Defaults to ./.streerc.

      --ignore-files=...
        A glob pattern to ignore files when processing. This can be specified
        multiple times to ignore multiple patterns.

      --plugins=...
        A comma-separated list of plugins to load.

      --extension=...
        A file extension matching the content passed in via STDIN or -e.
        Defaults to '.rb'.

      --print-width=...
        The print width to use when formatting.

      --preferred-quote=...
        The preferred quote style to use when formatting. Valid styles are
        single, double, ', and ".

      --[no-]trailing-comma
        Whether or not to add trailing commas to multi-line collections and
        method calls.

      SOURCE:

      -e ...
        Parse an inline string.

      path
        One or more file paths or glob patterns to process.
    HELP

    # This represents all of the options that can be passed to the CLI. It is
    # responsible for parsing the list and then returning the file paths at the
    # end.
    class Options
      attr_reader :ignore_files, :plugins, :scripts, :extension
      attr_reader :print_width, :preferred_quote, :trailing_comma

      def initialize(arguments)
        @ignore_files = []
        @plugins = []
        @scripts = []
        @extension = ".rb"

        @print_width = :default
        @preferred_quote = :default
        @trailing_comma = :default

        parser.parse!(arguments)
      end

      def options
        SyntaxTree.options(
          print_width: print_width,
          preferred_quote: preferred_quote,
          trailing_comma: trailing_comma
        )
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

          # If there is a script specified on the command line, then parse
          # it and add it to the list of scripts to run.
          opts.on("-e SCRIPT") { |script| @scripts << script }

          # If there is a extension specified, then parse it and use it for
          # STDIN and scripts.
          opts.on("--extension=EXTENSION") do |extension|
            # Both ".rb" and "rb" are going to work
            @extension = ".#{extension.delete_prefix(".")}"
          end

          # If there is a print width specified on the command line, then
          # parse that out here and use it when formatting.
          opts.on("--print-width=NUMBER", Integer) { |print_width| @print_width = print_width }

          # If there is a preferred quote style specified on the command line,
          # then parse that out here and use it when formatting.
          opts.on("--preferred-quote=STYLE") do |preferred_quote|
            @preferred_quote =
              case preferred_quote
              when "single", "'"
                "'"
              when "double", '"'
                '"'
              else
                raise ArgumentError, "Invalid preferred quote style: #{preferred_quote}"
              end
          end

          # If there is a trailing comma style specified on the command line,
          # then parse that out here and use it when formatting.
          opts.on("--[no-]trailing-comma") { |trailing_comma| @trailing_comma = trailing_comma }
        end
      end
    end

    # We allow a minimal configuration file to act as additional command line
    # arguments to the CLI. Each line of the config file should be a new
    # argument, as in:
    #
    #     --print-width=100
    #     --trailing-comma
    #
    # When invoking the CLI, we will read this config file and then parse it if
    # it exists in the current working directory.
    class ConfigFile
      FILENAME = ".streerc"

      attr_reader :filepath

      def initialize(filepath = nil)
        if filepath
          if File.readable?(filepath)
            @filepath = filepath
          else
            raise ArgumentError, "Invalid configuration file: #{filepath}"
          end
        else
          @filepath = File.join(Dir.pwd, FILENAME)
        end
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

        # First, we need to check if there's a --config option specified
        # so we can use the custom config file path.
        config_filepath = nil
        arguments.each_with_index do |arg, index|
          if arg.start_with?("--config=")
            config_filepath = arg.split("=", 2)[1]
            arguments.delete_at(index)
            break
          elsif arg == "--config" && arguments[index + 1]
            config_filepath = arguments[index + 1]
            arguments.delete_at(index + 1)
            arguments.delete_at(index)
            break
          end
        end

        config_file = ConfigFile.new(config_filepath)
        arguments = config_file.arguments.concat(arguments)

        options = Options.new(arguments)
        action =
          case name
          when "c", "check"
            Check.new(options.options)
          when "debug"
            Debug.new(options.options)
          when "f", "format"
            Format.new(options.options)
          when "help"
            puts HELP
            return 0
          when "lsp"
            LSP.new(options: options.options, ignore_files: options.ignore_files).run
            return 0
          when "version"
            puts VERSION
            return 0
          when "w", "write"
            Write.new(options.options)
          else
            warn(HELP)
            return 1
          end

        # We're going to build up a queue of items to process.
        queue = []

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

          options.scripts.each { |script| queue << ScriptItem.new(script, options.extension) }
        else
          queue << STDINItem.new(options.extension)
        end

        # At the end, we're going to return whether or not this CLI ever
        # encountered an error.
        if process_queue(action, queue)
          action.failure
          1
        else
          action.success
          0
        end
      end

      private

      def process_item(item, action)
        action.run(item)
        false
      rescue ParseError => error
        warn("syntax error:\n#{error.message}")
        true
      rescue Check::UnformattedError, Debug::NonIdempotentFormatError
        true
      rescue StandardError => error
        warn(error.message)
        warn(error.backtrace)
        true
      end

      if Process.respond_to?(:fork)
        def process_queue(action, queue)
          queue.freeze
          nworkers = [Etc.nprocessors - 1, queue.size].min

          requests = Array.new(nworkers) { IO.pipe }
          responses = Array.new(nworkers) { IO.pipe }

          pids =
            nworkers.times.map do |nworker|
              # In each child process, we will continuously write to the request
              # pipe when we are available for work. The parent process will
              # then write back on the response pipe either an index to work on
              # or a -1 to indicate that there is no more work to be done. At
              # the end of the loop, we will write the status of our work back
              # to the parent process to indicate if there were any errors.
              fork do
                requests.each_with_index do |(reader, writer), npipe|
                  reader.close
                  writer.close if npipe != nworker
                end

                responses.each_with_index do |(reader, writer), npipe|
                  writer.close
                  reader.close if npipe != nworker
                end

                request_writer = requests[nworker][1]
                response_reader = responses[nworker][0]
                errored = false

                loop do
                  request_writer.puts(0)
                  break if (response = Integer(response_reader.gets)) == -1
                  errored |= process_item(queue[response], action)
                end

                request_writer.puts(errored ? -1 : 1)
                request_writer.close
                response_reader.close
              end
            end

          requests.each { |(_, writer)| writer.close }
          responses.each { |(reader, _)| reader.close }

          indices = queue.each_index
          errored = false

          request_readers = requests.map(&:first)
          response_writers =
            requests.zip(responses).to_h { |(reader, _), (_, writer)| [reader, writer] }

          # The parent process will continuously listen for requests from the
          # child processes and respond accordingly. When the child processes
          # write that they are ready for work, we will send them the next index
          # to work on. When they write that they are done, we will remove them
          # from the list of active workers.
          until request_readers.empty?
            IO
              .select(request_readers)[0]
              .each do |request_reader|
                case Integer(request_reader.gets)
                when 0
                  response_writer = response_writers[request_reader]

                  begin
                    response_writer.puts(indices.next)
                  rescue StopIteration
                    response_writer.puts(-1)
                  end
                when -1
                  errored = true
                  request_readers.delete(request_reader)
                when 1
                  request_readers.delete(request_reader)
                end
              end
          end

          pids.each { |pid| Process.waitpid(pid) }
          errored
        end
      else
        def process_queue(action, queue)
          queue = Queue.new(queue).tap(&:close)
          workers = [Etc.nprocessors, queue.size].min
            .times
            .map do
              Thread.new do
                Thread.current.abort_on_exception = true
                errored = false

                while (item = queue.shift)
                  errored |= process_item(item, action)
                end

                errored
              end
            end

          workers.map(&:value).any?
        end
      end
    end
  end
end
