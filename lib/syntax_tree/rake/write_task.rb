# frozen_string_literal: true

require_relative "task"

module SyntaxTree
  module Rake
    # A Rake task that runs write on a set of source files.
    #
    # Example:
    #
    #   require "syntax_tree/rake/write_task"
    #
    #   SyntaxTree::Rake::WriteTask.new do |t|
    #     t.source_files = "{app,config,lib}/**/*.rb"
    #   end
    #
    # This will create task that can be run with:
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
