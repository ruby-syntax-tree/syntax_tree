# frozen_string_literal: true

# This file's purpose is to extract the examples from the whitequark/parser
# gem and generate a test file that we can use to ensure that our parser
# generates equivalent syntax trees when translating. To do this, it runs the
# parser's test suite but overrides the `assert_parses` method to collect the
# examples into a hash. Then, it writes out the hash to a file that we can use
# to generate our own tests.
#
# To run the test suite, it's important to note that we have to mirror both any
# APIs provided to the test suite (for example the ParseHelper module below).
# This is obviously relatively brittle, but it's effective for now.

require "ast"

module ParseHelper
  # This object is going to collect all of the examples from the parser gem into
  # a hash that we can use to generate our own tests.
  COLLECTED = Hash.new { |hash, key| hash[key] = [] }

  include AST::Sexp
  ALL_VERSIONS = %w[3.1 3.2]

  private

  def assert_context(*)
  end

  def assert_diagnoses(*)
  end

  def assert_diagnoses_many(*)
  end

  def refute_diagnoses(*)
  end

  def with_versions(*)
  end

  def assert_parses(_ast, code, _source_maps = "", versions = ALL_VERSIONS)
    # We're going to skip any examples that are for older Ruby versions
    # that we do not support.
    return if (versions & %w[3.1 3.2]).empty?

    entry =
      caller.find do |call|
        call.include?("test_parser.rb") && call.match?(%r{(?<!/)test_})
      end

    _, lineno, name =
      *entry.match(/(\d+):in [`'](?:block in )?(?:TestParser#)?(.+)'/)

    COLLECTED["#{name}:#{lineno}"] << code
  end
end

namespace :extract do
  desc "Extract the whitequark/parser tests"
  task :whitequark do
    directory = File.expand_path("../tmp/parser", __dir__)
    unless File.directory?(directory)
      sh "git clone --depth 1 https://github.com/whitequark/parser #{directory}"
    end

    mkdir_p "#{directory}/extract"
    touch "#{directory}/extract/helper.rb"
    touch "#{directory}/extract/parse_helper.rb"
    touch "#{directory}/extract/extracted.txt"
    $:.unshift "#{directory}/extract"

    require "parser/current"
    require "minitest/autorun"
    require_relative "#{directory}/test/test_parser"

    Minitest.after_run do
      filepath = File.expand_path("../test/translation/parser.txt", __dir__)

      File.open(filepath, "w") do |file|
        ParseHelper::COLLECTED.sort.each do |(key, codes)|
          if codes.length == 1
            file.puts("!!! #{key}\n#{codes.first}")
          else
            codes.each_with_index do |code, index|
              file.puts("!!! #{key}:#{index}\n#{code}")
            end
          end
        end
      end
    end
  end
end
