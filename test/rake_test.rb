# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class RakeTest < Minitest::Test
    def test_check_task
      source_files = "{app,config,lib}/**/*.rb"
      print_width = SyntaxTree.options.print_width + 1

      Rake::CheckTask.new do |t|
        t.source_files = source_files
        t.print_width = print_width
      end

      expected = ["check", "--print-width=#{print_width}", source_files]
      assert_equal(expected, invoke("stree:check"))
    end

    def test_write_task
      source_files = "{app,config,lib}/**/*.rb"
      trailing_comma = !SyntaxTree.options.trailing_comma

      Rake::WriteTask.new do |t|
        t.source_files = source_files
        t.trailing_comma = trailing_comma
      end

      expected = ["write", "--#{"no-" unless trailing_comma}trailing-comma", source_files]
      assert_equal(expected, invoke("stree:write"))
    end

    private

    def invoke(task_name)
      invocation = nil
      stub = ->(args) { invocation = args }

      assert_raises SystemExit do
        SyntaxTree::CLI.stub(:run, stub) { ::Rake::Task[task_name].invoke }
      end

      invocation
    end
  end
end
