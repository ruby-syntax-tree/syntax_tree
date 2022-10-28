# frozen_string_literal: true

require "rake"
require "rake/tasklib"

require "syntax_tree"
require "syntax_tree/cli"

module SyntaxTree
  module Rake
    # A parent Rake task that runs a command on a set of source files.
    class Task < ::Rake::TaskLib
      # Name of the task.
      attr_accessor :name

      # Glob pattern to match source files.
      # Defaults to 'lib/**/*.rb'.
      attr_accessor :source_files

      # The set of plugins to require.
      # Defaults to [].
      attr_accessor :plugins

      # Max line length.
      # Defaults to 80.
      attr_accessor :print_width

      # The target Ruby version to use for formatting.
      # Defaults to Gem::Version.new(RUBY_VERSION).
      attr_accessor :target_ruby_version

      # Glob pattern to ignore source files.
      # Defaults to ''.
      attr_accessor :ignore_files

      def initialize(
        name = :"stree:#{command}",
        source_files = ::Rake::FileList["lib/**/*.rb"],
        plugins = [],
        print_width = DEFAULT_PRINT_WIDTH,
        target_ruby_version = Gem::Version.new(RUBY_VERSION),
        ignore_files = ""
      )
        @name = name
        @source_files = source_files
        @plugins = plugins
        @print_width = print_width
        @target_ruby_version = target_ruby_version
        @ignore_files = ignore_files

        yield self if block_given?
        define_task
      end

      private

      # This method needs to be overridden in the child tasks.
      def command
        raise NotImplementedError
      end

      def define_task
        desc "Runs `stree #{command}` over source files"
        task(name) { run_task }
      end

      def run_task
        arguments = [command]
        arguments << "--plugins=#{plugins.join(",")}" if plugins.any?

        if print_width != DEFAULT_PRINT_WIDTH
          arguments << "--print-width=#{print_width}"
        end

        if target_ruby_version != Gem::Version.new(RUBY_VERSION)
          arguments << "--target-ruby-version=#{target_ruby_version}"
        end

        arguments << "--ignore-files=#{ignore_files}" if ignore_files != ""

        abort if SyntaxTree::CLI.run(arguments + Array(source_files)) != 0
      end
    end
  end
end
