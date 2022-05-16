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

      def initialize(
        name = :"stree:write",
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
        desc "Runs `stree write` over source files"
        task(name) { run_task }
      end

      def run_task
        arguments = ["write"]
        arguments << "--plugins=#{plugins.join(",")}" if plugins.any?

        SyntaxTree::CLI.run(arguments + Array(source_files))
      end
    end
  end
end
