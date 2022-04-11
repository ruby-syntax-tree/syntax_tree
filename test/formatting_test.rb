# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class FormattingTest < Minitest::Test
    FIXTURES_3_0_0 = %w[
      command_def_endless
      def_endless
      fndptn
      rassign
      rassign_rocket
    ]

    FIXTURES_3_1_0 = %w[
      pinned_begin
      var_field_rassign
    ]

    fixtures = Dir[File.join(__dir__, "fixtures", "*.rb")].map { |filepath| File.basename(filepath, ".rb") }
    fixtures -= FIXTURES_3_1_0 if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1.0")
    fixtures -= FIXTURES_3_0_0 if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.0.0")

    delimiter = /%(?: # (.+?))?\n/
    fixtures.each do |fixture|
      filepath = File.join(__dir__, "fixtures", "#{fixture}.rb")

      File.readlines(filepath).slice_before(delimiter).each_with_index do |source, index|
        comment = source.shift.match(delimiter)[1]
        original, expected = source.join.split("-\n")

        # If there's a comment starting with >= that starts after the % that
        # delineates the test, then we're going to check if the version
        # satisfies that constraint.
        if comment&.start_with?(">=")
          version = Gem::Version.new(comment.split[1])
          next if Gem::Version.new(RUBY_VERSION) < version
        end

        define_method(:"test_formatting_#{fixture}_#{index}") do
          assert_equal(expected || original, SyntaxTree.format(original))
        end
      end
    end
  end
end
