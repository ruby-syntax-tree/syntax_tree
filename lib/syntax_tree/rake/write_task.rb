# frozen_string_literal: true

require "rake"
require "rake/tasklib"

require "syntax_tree"
require "syntax_tree/cli"

module SyntaxTree
  module Rake
    # A Rake task that runs format on a set of source files.
    #
    # Example:
    #
    #   require 'syntax_tree/rake/write_task'
    #
    #   SyntaxTree::Rake::WriteTask.new do |t|
    #     t.source_files = '{app,config,lib}/**/*.rb'
    #   end
    #
    # This will create task that can be run with:
    #
    #   rake stree_write
    #
    class WriteTask < ::Rake::TaskLib
      # Name of the task.
      # Defaults to :"stree:write".
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

      def initialize(
        name = :"stree:write",
        source_files = ::Rake::FileList["lib/**/*.rb"],
        plugins = [],
        print_width = DEFAULT_PRINT_WIDTH,
        target_ruby_version = Gem::Version.new(RUBY_VERSION)
      )
        @name = name
        @source_files = source_files
        @plugins = plugins
        @print_width = print_width
        @target_ruby_version = target_ruby_version

        yield self if block_given?
        define_task
      end

      private

      def define_task
        desc "Runs `stree write` over source files"
        task(name) { run_task }
      end

      def run_task
        arguments = ["write"]
        arguments << "--plugins=#{plugins.join(",")}" if plugins.any?

        if print_width != DEFAULT_PRINT_WIDTH
          arguments << "--print-width=#{print_width}"
        end

        if target_ruby_version != Gem::Version.new(RUBY_VERSION)
          arguments << "--target-ruby-version=#{target_ruby_version}"
        end

        SyntaxTree::CLI.run(arguments + Array(source_files))
      end
    end
  end
end
