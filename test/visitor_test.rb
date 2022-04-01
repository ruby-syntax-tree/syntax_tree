# frozen_string_literal: true

require_relative "test_helper"

class VisitorTest < Minitest::Test
  def test_visit_all_nodes
    visitor = SyntaxTree::Visitor.new

    filepath = File.expand_path("../lib/syntax_tree/node.rb", __dir__)
    program = SyntaxTree.parse(SyntaxTree.read(filepath))

    program.statements.body.last.bodystmt.statements.body.each do |node|
      next unless node in SyntaxTree::ClassDeclaration[superclass: { value: { value: "Node" } }]

      accept = node.bodystmt.statements.body.detect { |defm| defm in SyntaxTree::Def[name: { value: "accept" }] }
      accept => { bodystmt: { statements: { body: [SyntaxTree::Call[message: { value: visit_method }]] } } }

      assert_respond_to(visitor, visit_method)
    end
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

    visit_method def visit_class(node)
      @visited_nodes << node.constant.constant.value
      super
    end

    visit_method def visit_def(node)
      @visited_nodes << node.name.value
    end
  end
end
