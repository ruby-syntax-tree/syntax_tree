# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/rake/task"

module SyntaxTree
  class TaskTest < Minitest::Test
    Invoke = Struct.new(:args)

    def test_task
      source_files = "{app,config,lib}/**/*.rb"

      SyntaxTree::Rake::Task.new do |t|
        t.source_files = source_files
      end

      invoke = []
      SyntaxTree::CLI.stub(:run, ->(args) { invoke << Invoke.new(args) }) do
        ::Rake::Task["check_and_format"].invoke
      end

      assert_equal(
        [["check", source_files], ["format", source_files]], invoke.map(&:args)
      )
    end
  end
end
