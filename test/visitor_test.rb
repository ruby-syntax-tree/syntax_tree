# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class VisitorTest < Minitest::Test
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
      assert_equal(%w[Foo foo Bar bar baz], visitor.visited_nodes)
    end

    class DummyVisitor < Visitor
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

    if defined?(DidYouMean.correct_error)
      def test_visit_method_correction
        error = assert_raises { Visitor.visit_method(:visit_binar) }
        message =
          if Exception.method_defined?(:detailed_message)
            error.detailed_message
          else
            error.message
          end

        assert_match(/visit_binary/, message)
      end
    end

    class VisitMethodsTestVisitor < BasicVisitor
    end

    def test_visit_methods
      VisitMethodsTestVisitor.visit_methods do
        assert_raises(BasicVisitor::VisitMethodError) do
          # In reality, this would be a method defined using the def keyword,
          # but we're using method_added here to trigger the checker so that we
          # aren't defining methods dynamically in the test suite.
          VisitMethodsTestVisitor.method_added(:visit_foo)
        end
      end
    end
  end
end
