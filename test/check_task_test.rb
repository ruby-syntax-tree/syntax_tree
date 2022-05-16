# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/rake/check_task"

module SyntaxTree
  class CheckTaskTest < Minitest::Test
    Invoke = Struct.new(:args)

    def test_task
      source_files = "{app,config,lib}/**/*.rb"

      SyntaxTree::Rake::CheckTask.new { |t| t.source_files = source_files }

      invoke = nil
      SyntaxTree::CLI.stub(:run, ->(args) { invoke = Invoke.new(args) }) do
        ::Rake::Task["stree_check"].invoke
      end

      assert_equal(["check", source_files], invoke.args)
    end
  end
end
