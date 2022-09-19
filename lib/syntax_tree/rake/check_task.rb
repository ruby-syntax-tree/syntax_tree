# frozen_string_literal: true

require_relative "task"

module SyntaxTree
  module Rake
    # A Rake task that runs check on a set of source files.
    #
    # Example:
    #
    #   require "syntax_tree/rake/check_task"
    #
    #   SyntaxTree::Rake::CheckTask.new do |t|
    #     t.source_files = "{app,config,lib}/**/*.rb"
    #   end
    #
    # This will create task that can be run with:
    #
    #   rake stree:check
    #
    class CheckTask < Task
      private

      def command
        "check"
      end
    end
  end
end
