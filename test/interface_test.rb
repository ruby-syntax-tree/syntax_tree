# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class InterfaceTest < Minitest::Test
    ObjectSpace.each_object(Node.singleton_class) do |klass|
      next if klass == Node

      define_method(:"test_instantiate_#{klass.name}") do
        assert_syntax_tree(instantiate(klass))
      end
    end

    Fixtures.each_fixture do |fixture|
      define_method(:"test_#{fixture.name}") do
        assert_syntax_tree(SyntaxTree.parse(fixture.source))
      end
    end

    private

    # This method is supposed to instantiate a new instance of the given class.
    # The class is always a descendant from SyntaxTree::Node, so we can make
    # certain assumptions about the way the initialize method is set up. If it
    # needs to be special-cased, it's done so at the end of this method.
    def instantiate(klass)
      params = {}

      # Set up all of the keyword parameters for the class.
      klass
        .instance_method(:initialize)
        .parameters
        .each { |(type, name)| params[name] = nil if type.start_with?("key") }

      # Set up any default values that have to be arrays.
      %i[
        assocs
        comments
        elements
        keywords
        locals
        optionals
        parts
        posts
        requireds
        symbols
        values
      ].each { |key| params[key] = [] if params.key?(key) }

      # Set up a default location for the node.
      params[:location] = Location.fixed(line: 0, char: 0, column: 0)

      case klass.name
      when "SyntaxTree::Binary"
        klass.new(**params, operator: :+)
      when "SyntaxTree::Label"
        klass.new(**params, value: "label:")
      when "SyntaxTree::RegexpLiteral"
        klass.new(**params, ending: "/")
      when "SyntaxTree::Statements"
        klass.new(nil, **params, body: [])
      else
        klass.new(**params)
      end
    end
  end
end
