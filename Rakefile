# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"
require "syntax_tree/rake"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

configure = ->(task) do
  task.source_files =
    FileList[%w[Gemfile Rakefile syntax_tree.gemspec lib/**/*.rb tasks/*.rake test/*.rb]]
end

SyntaxTree::Rake::CheckTask.new(&configure)
SyntaxTree::Rake::WriteTask.new(&configure)
