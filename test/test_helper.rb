# frozen_string_literal: true

require "simplecov"
SimpleCov.start do
  add_filter("idempotency_test.rb") unless ENV["CI"]
  add_group("lib", "lib")
  add_group("test", "test")
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "syntax_tree"
require "syntax_tree/cli"

# Here we are going to establish type verification whenever a new node is
# created. We do this through the reflection module, which in turn parses the
# source code of the node classes.
require "syntax_tree/reflection"
SyntaxTree::Reflection.nodes.each do |name, node|
  next if name == :Statements

  clazz = SyntaxTree.const_get(name)
  parameters = clazz.instance_method(:initialize).parameters

  # First, verify that all of the parameters listed in the list of attributes.
  # If there are any parameters that aren't listed in the attributes, then
  # something went wrong with the parsing in the reflection module.
  raise unless (parameters.map(&:last) - node.attributes.keys).empty?

  # Now we're going to use an alias chain to redefine the initialize method to
  # include type checking.
  clazz.alias_method(:initialize_without_verify, :initialize)
  clazz.define_method(:initialize) do |**kwargs|
    kwargs.each do |kwarg, value|
      attribute = node.attributes.fetch(kwarg)

      unless attribute.type === value
        raise TypeError,
              "invalid type for #{name}##{kwarg}, expected " \
                "#{attribute.type.inspect}, got #{value.inspect}"
      end
    end

    initialize_without_verify(**kwargs)
  end
end

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
      # First, get the visit method name.
      recorder = Recorder.new
      node.accept(recorder)

      # Next, get the "type" which is effectively an underscored version of
      # the name of the class.
      type = recorder.called[/^visit_(.+)$/, 1]

      # Test that the method that is called when you call accept is a valid
      # visit method on the visitor.
      assert_respond_to(Visitor.new, recorder.called)

      # Test that you can call child_nodes and the pattern matching methods on
      # this class.
      assert_kind_of(Array, node.child_nodes)
      assert_kind_of(Array, node.deconstruct)
      assert_kind_of(Hash, node.deconstruct_keys([]))

      # Assert that it can be pretty printed to a string.
      pretty = PP.singleline_pp(node, +"")
      refute_includes(pretty, "#<")
      assert_includes(pretty, type)

      # Assert that we can get back a new tree by using the mutation visitor.
      assert_operator node, :===, node.accept(MutationVisitor.new)

      # Serialize the node to JSON, parse it back out, and assert that we have
      # found the expected type.
      json = node.to_json
      refute_includes(json, "#<")
      assert_equal(type, JSON.parse(json)["type"])

      if RUBY_ENGINE != "truffleruby"
        # Get a match expression from the node, then assert that it can in fact
        # match the node.
        # rubocop:disable all
        assert(eval(<<~RUBY))
          case node
          in #{node.construct_keys}
            true
          end
        RUBY
      end
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
          if comment&.start_with?(">=")
            next if ruby_version < Gem::Version.new(comment.split[1])
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
