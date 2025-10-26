# frozen_string_literal: true

unless RUBY_ENGINE == "truffleruby"
  require "simplecov"
  SimpleCov.start do
    add_filter("idempotency_test.rb") unless ENV["CI"]
    add_filter("ractor_test.rb") unless ENV["CI"]
    add_group("lib", "lib")
    add_group("test", "test")
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "syntax_tree"
require "syntax_tree/cli"

require "json"
require "tempfile"
require "pp"
require "minitest/autorun"

module SyntaxTree
  module Assertions
    class Recorder
      attr_reader :called

      def initialize
        @called = nil
      end

      def method_missing(called, *, **)
        @called = called
      end
    end

    private

    # This is a special kind of assertion that is going to get loaded into all
    # of test cases. It asserts against a whole bunch of stuff that every node
    # type should be able to handle. It's here so that we can use it in a bunch
    # of tests.
    def assert_syntax_tree(node)
      recorder = Recorder.new
      node.accept(recorder)

      visitor = Parser::Visitor.new
      assert_respond_to(visitor, recorder.called)

      assert_kind_of(node.class, node.copy)
      assert_operator(node, :===, node)
      assert_kind_of(Array, node.child_nodes)
      assert_kind_of(Array, node.deconstruct)
      assert_kind_of(Hash, node.deconstruct_keys([]))
    end

    Minitest::Test.include(self)
  end
end

# There are a bunch of fixtures defined in test/fixtures. They exercise every
# possible combination of syntax that leads to variations in the types of nodes.
# They are used for testing various parts of Syntax Tree, including formatting,
# serialization, and parsing. This module provides a single each_fixture method
# that can be used to drive tests on each fixture.
module Fixtures
  FIXTURES_3_0_0 = %w[
    command_def_endless
    def_endless
    fndptn
    rassign
    rassign_rocket
  ].freeze

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
          if comment&.start_with?(">=") &&
               ruby_version < Gem::Version.new(comment.split[1])
            next
          end

          name = :"#{fixture}_#{index}"
          yield(
            Fixture.new(
              name: name,
              source: source,
              formatted: formatted || source
            )
          )
        end
    end
  end
end
