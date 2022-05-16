# frozen_string_literal: true

require "rake"
require "rake/tasklib"

require "syntax_tree"
require "syntax_tree/cli"

module SyntaxTree
  module Rake
    # A Rake task that runs check on a set of source files.
    #
    # Example:
    #
    #   require 'syntax_tree/rake/check_task'
    #
    #   SyntaxTree::Rake::CheckTask.new do |t|
    #     t.source_files = '{app,config,lib}/**/*.rb'
    #   end
    #
    # This will create task that can be run with:
    #
    #   rake stree_check
    #
    class CheckTask < ::Rake::TaskLib
      # Name of the task.
      # Defaults to :"stree:check".
      attr_accessor :name

      # Glob pattern to match source files.
      # Defaults to 'lib/**/*.rb'.
      attr_accessor :source_files

      # The set of plugins to require.
      # Defaults to [].
      attr_accessor :plugins

      def initialize(
        name = :"stree:check",
        source_files = ::Rake::FileList["lib/**/*.rb"],
        plugins = []
      )
        @name = name
        @source_files = source_files
        @plugins = plugins

        yield self if block_given?
        define_task
      end

      private

      def define_task
        desc "Runs `stree check` over source files"
        task(name) { run_task }
      end

      def run_task
        arguments = ["check"]
        arguments << "--plugins=#{plugins.join(",")}" if plugins.any?

        SyntaxTree::CLI.run(arguments + Array(source_files))
      end
    end
  end
end
