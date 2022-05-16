# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/rake_tasks"

module SyntaxTree
  module Rake
    class CheckTaskTest < Minitest::Test
      Invoke = Struct.new(:args)

      def test_check_task
        source_files = "{app,config,lib}/**/*.rb"
        CheckTask.new { |t| t.source_files = source_files }

        invoke = nil
        SyntaxTree::CLI.stub(:run, ->(args) { invoke = Invoke.new(args) }) do
          ::Rake::Task["stree:check"].invoke
        end

        assert_equal(["check", source_files], invoke.args)
      end

      def test_write_task
        source_files = "{app,config,lib}/**/*.rb"
        WriteTask.new { |t| t.source_files = source_files }

        invoke = nil
        SyntaxTree::CLI.stub(:run, ->(args) { invoke = Invoke.new(args) }) do
          ::Rake::Task["stree:write"].invoke
        end

        assert_equal(["write", source_files], invoke.args)
      end
    end
  end
end
