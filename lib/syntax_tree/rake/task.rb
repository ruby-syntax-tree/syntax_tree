# frozen_string_literal: true

require "rake"
require "rake/tasklib"

module SyntaxTree
  module Rake
    # A Rake task that runs check and format on a set of source files.
    #
    # Example:
    #
    #   require 'syntax_tree/rake/task'
    #
    #   SyntaxTree::Rake::Task.new do |t|
    #     t.source_files = '{app,config,lib}/**/*.rb'
    #   end
    #
    # This will create task that can be run with:
    #
    #   rake syntax_tree:check_and_format
    class Task < ::Rake::TaskLib
      # Glob pattern to match source files.
      # Defaults to 'lib/**/*.rb'.
      attr_accessor :source_files

      def initialize
        @source_files = "lib/**/*.rb"

        yield self if block_given?
        define_task
      end

      private

      def define_task
        desc "Runs syntax_tree over source files"
        task(:check_and_format) { run_task }
      end

      def run_task
        %w[check format].each do |command|
          SyntaxTree::CLI.run([command, source_files].compact)
        end

        # TODO: figure this out
        # exit($?.exitstatus) if $?&.exited?
      end
    end
  end
end
