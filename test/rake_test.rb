# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/rake_tasks"

module SyntaxTree
  module Rake
    class CheckTaskTest < Minitest::Test
      Invocation = Struct.new(:args)

      def test_task_command
        assert_raises(NotImplementedError) { Task.new.command }
      end

      def test_check_task
        source_files = "{app,config,lib}/**/*.rb"

        CheckTask.new do |t|
          t.source_files = source_files
          t.print_width = 100
          t.target_ruby_version = Gem::Version.new("2.6.0")
        end

        expected = [
          "check",
          "--print-width=100",
          "--target-ruby-version=2.6.0",
          source_files
        ]

        invocation = invoke("stree:check")
        assert_equal(expected, invocation.args)
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

        assert_raises SystemExit do
          SyntaxTree::CLI.stub(:run, stub) { ::Rake::Task[task_name].invoke }
        end

        invocation
      end
    end
  end
end
