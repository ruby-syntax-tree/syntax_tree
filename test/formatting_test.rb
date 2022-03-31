# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class FormattingTest < Minitest::Test
    delimiter = /%(?: # (.+?))?\n/

    Dir[File.join(__dir__, "fixtures", "*.rb")].each do |filepath|
      basename = File.basename(filepath, ".rb")
      sources = File.readlines(filepath).slice_before(delimiter)

      sources.each_with_index do |source, index|
        comment = source.shift.match(delimiter)[1]
        original, expected = source.join.split("-\n")

        # If there's a comment starting with >= that starts after the % that
        # delineates the test, then we're going to check if the version
        # satisfies that constraint.
        if comment&.start_with?(">=")
          version = Gem::Version.new(comment.split[1])
          next if Gem::Version.new(RUBY_VERSION) < version
        end

        define_method(:"test_formatting_#{basename}_#{index}") do
          assert_equal(expected || original, SyntaxTree.format(original))
        end
      end
    end
  end
end
