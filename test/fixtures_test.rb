# frozen_string_literal: true

require_relative "test_helper"

# There are a bunch of fixtures defined in test/fixtures. They exercise every
# possible combination of syntax that leads to variations in the types of nodes.
# They are used for testing various parts of Syntax Tree, including formatting,
# serialization, and parsing. This module provides a single each_fixture method
# that can be used to drive tests on each fixture.
module Fixtures
  FIXTURES_3_0_0 = %w[command_def_endless def_endless fndptn rassign rassign_rocket].freeze

  FIXTURES_3_1_0 = %w[pinned_begin var_field_rassign].freeze

  Fixture = Struct.new(:name, :source, :formatted, keyword_init: true)

  def self.each_fixture
    ruby_version = Gem::Version.new(RUBY_VERSION)

    # First, get a list of the basenames of all of the fixture files.
    fixtures =
      Dir[File.expand_path("fixtures/*.rb", __dir__)].map do |filepath|
        File.basename(filepath, ".rb")
      end

    # Next, subtract out any fixtures that aren't supported by the current Ruby
    # version.
    fixtures -= FIXTURES_3_1_0 if ruby_version < Gem::Version.new("3.1.0")
    fixtures -= FIXTURES_3_0_0 if ruby_version < Gem::Version.new("3.0.0")

    delimiter = /%(?: # (.+?))?\n/
    fixtures.each do |fixture|
      filepath = File.expand_path("fixtures/#{fixture}.rb", __dir__)

      # For each fixture in the fixture file yield a Fixture object.
      File
        .readlines(filepath)
        .slice_before(delimiter)
        .each_with_index do |source, index|
          comment = source.shift.match(delimiter)[1]
          source, formatted = source.join.split("-\n")

          # If there's a comment starting with >= that starts after the % that
          # delineates the test, then we're going to check if the version
          # satisfies that constraint.
          next if comment&.start_with?(">=") && ruby_version < Gem::Version.new(comment.split[1])

          name = :"#{fixture}_#{index}"
          yield(Fixture.new(name: name, source: source, formatted: formatted || source))
        end
    end
  end
end

module SyntaxTree
  class FixturesTest < Minitest::Test
    Fixtures.each_fixture do |fixture|
      define_method(:"test_formatted_#{fixture.name}") do
        options = SyntaxTree.options(print_width: 80)
        assert_equal(fixture.formatted, SyntaxTree.format(fixture.source, options))
      end
    end
  end
end
