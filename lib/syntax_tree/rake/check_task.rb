# frozen_string_literal: true

require "rake"
require "rake/tasklib"

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
      # Defaults to :stree_check.
      attr_accessor :name

      # Glob pattern to match source files.
      # Defaults to 'lib/**/*.rb'.
      attr_accessor :source_files

      def initialize(name = :stree_check)
        @name = name
        @source_files = "lib/**/*.rb"

        yield self if block_given?
        define_task
      end

      private

      def define_task
        desc "Runs `stree check` over source files"
        task(name) { run_task }
      end

      def run_task
        SyntaxTree::CLI.run(["check", source_files].compact)

        # exit($?.exitstatus) if $?&.exited?
      end
    end
  end
end
