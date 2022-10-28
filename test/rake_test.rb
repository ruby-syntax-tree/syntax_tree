# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/rake_tasks"

module SyntaxTree
  module Rake
    class CheckTaskTest < Minitest::Test
      Invocation = Struct.new(:args)

      def test_check_task
        source_files = "{app,config,lib}/**/*.rb"
        CheckTask.new { |t| t.source_files = source_files }

        invocation = invoke("stree:check")
        assert_equal(["check", source_files], invocation.args)
      end

      def test_write_task
        source_files = "{app,config,lib}/**/*.rb"
        WriteTask.new { |t| t.source_files = source_files }

        invocation = invoke("stree:write")
        assert_equal(["write", source_files], invocation.args)
      end

      private

      def invoke(task_name)
        invocation = nil
        stub = ->(args) { invocation = Invocation.new(args) }

        begin
          SyntaxTree::CLI.stub(:run, stub) { ::Rake::Task[task_name].invoke }
          flunk
        rescue SystemExit
          invocation
        end
      end
    end
  end
end
