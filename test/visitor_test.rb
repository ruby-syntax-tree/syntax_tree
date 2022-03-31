# frozen_string_literal: true

require_relative "test_helper"
require "objspace"

class VisitorTest < Minitest::Test
  def test_can_visit_all_nodes
    visitor = SyntaxTree::Visitor.new

    ObjectSpace.each_object(SyntaxTree::Node.singleton_class)
      .reject { |node| node.singleton_class? || node == SyntaxTree::Node }
      .each { |node| assert_respond_to(visitor, node.visit_method_name) }
  end

  def test_node_visit_method_name
    assert_equal("visit_t_string_end", SyntaxTree::TStringEnd.visit_method_name)
  end

  def test_visit_tree
    parsed_tree = SyntaxTree.parse(<<~RUBY)
      class Foo
        def foo; end

        class Bar
          def bar; end
        end
      end

      def baz; end
    RUBY

    visitor = DummyVisitor.new
    visitor.visit(parsed_tree)
    assert_equal(["Foo", "foo", "Bar", "bar", "baz"], visitor.visited_nodes)
  end

  class DummyVisitor < SyntaxTree::Visitor
    attr_reader :visited_nodes

    def initialize
      super
      @visited_nodes = []
    end

    def visit_class_declaration(node)
      @visited_nodes << node.constant.constant.value
      super
    end

    def visit_def(node)
      @visited_nodes << node.name.value
    end
  end
end
