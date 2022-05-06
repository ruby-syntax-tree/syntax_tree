# frozen_string_literal: true

require "bundler/gem_tasks"
require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

task default: :test

FILEPATHS = %w[
  Gemfile
  Rakefile
  syntax_tree.gemspec
  lib/**/*.rb
  test/*.rb
].freeze

task :syntax_tree do
  $:.unshift File.expand_path("lib", __dir__)
  require "syntax_tree"
  require "syntax_tree/cli"
end

task check: :syntax_tree do
  exit SyntaxTree::CLI.run(["check"] + FILEPATHS)
end

task format: :syntax_tree do
  exit SyntaxTree::CLI.run(["write"] + FILEPATHS)
end
