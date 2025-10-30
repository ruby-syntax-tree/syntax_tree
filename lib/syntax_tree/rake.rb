# frozen_string_literal: true

require "syntax_tree"
require "rake"
require "rake/tasklib"

module SyntaxTree
  module Rake
    # A parent Rake task that runs a command on a set of source files.
    class Task < ::Rake::TaskLib
      # Name of the task.
      attr_accessor :name

      # Glob pattern to match source files. Defaults to 'lib/**/*.rb'.
      attr_accessor :source_files

      # Glob pattern to ignore source files. String. Optional.
      attr_accessor :ignore_files

      # List of plugins to load. Array of strings. Optional.
      attr_accessor :plugins

      # Print width for the formatter. Integer. Optional.
      attr_accessor :print_width

      # Preferred quote style. " or '. Optional.
      attr_accessor :preferred_quote

      # Trailing comma style. Boolean. Optional.
      attr_accessor :trailing_comma

      def initialize(
        name = :"stree:#{command}",
        source_files = ::Rake::FileList["lib/**/*.rb"],
        ignore_files = "",
        plugins = [],
        print_width = :default,
        preferred_quote = :default,
        trailing_comma = :default
      )
        @name = name

        @source_files = source_files
        @ignore_files = ignore_files
        @plugins = plugins

        @print_width = print_width
        @preferred_quote = preferred_quote
        @trailing_comma = trailing_comma

        yield self if block_given?
        define_task
      end

      private

      def command
        raise NotImplementedError
      end

      def define_task
        desc "Runs `stree #{command}` over source files"
        task(name) do
          arguments = [command]

          arguments << "--ignore-files=#{ignore_files}" if ignore_files != ""
          arguments << "--plugins=#{plugins.join(",")}" if plugins.any?

          arguments << "--print-width=#{print_width}" if print_width != :default
          arguments << "--preferred-quote=#{preferred_quote}" if preferred_quote != :default

          if trailing_comma != :default
            arguments << "--#{"no-" unless trailing_comma}trailing-comma"
          end

          arguments.concat(Array(source_files))
          abort if CLI.run(arguments) != 0
        end
      end
    end

    private_constant :Task

    # A Rake task that runs check on a set of source files.
    #
    # Example:
    #
    #   require "syntax_tree/rake"
    #
    #   SyntaxTree::Rake::CheckTask.new do |t|
    #     t.source_files = "{app,config,lib}/**/*.rb"
    #   end
    #
    # This will create a task that can be run with:
    #
    #   rake stree:check
    #
    class CheckTask < Task
      private

      def command
        "check"
      end
    end

    # A Rake task that runs write on a set of source files.
    #
    # Example:
    #
    #   require "syntax_tree/rake"
    #
    #   SyntaxTree::Rake::WriteTask.new do |t|
    #     t.source_files = "{app,config,lib}/**/*.rb"
    #   end
    #
    # This will create a task that can be run with:
    #
    #   rake stree:write
    #
    class WriteTask < Task
      private

      def command
        "write"
      end
    end
  end
end
