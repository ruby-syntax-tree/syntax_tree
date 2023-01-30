# frozen_string_literal: true

module SyntaxTree
  # BasicVisitor is the parent class of the Visitor class that provides the
  # ability to walk down the tree. It does not define any handlers, so you
  # should extend this class if you want your visitor to raise an error if you
  # attempt to visit a node that you don't handle.
  class BasicVisitor
    # This is raised when you use the Visitor.visit_method method and it fails.
    # It is correctable to through DidYouMean.
    class VisitMethodError < StandardError
      attr_reader :visit_method

      def initialize(visit_method)
        @visit_method = visit_method
        super("Invalid visit method: #{visit_method}")
      end
    end

    # This class is used by DidYouMean to offer corrections to invalid visit
    # method names.
    class VisitMethodChecker
      attr_reader :visit_method

      def initialize(error)
        @visit_method = error.visit_method
      end

      def corrections
        @corrections ||=
          DidYouMean::SpellChecker.new(
            dictionary: BasicVisitor.valid_visit_methods
          ).correct(visit_method)
      end

      # In some setups with Ruby you can turn off DidYouMean, so we're going to
      # respect that setting here.
      if defined?(DidYouMean.correct_error)
        DidYouMean.correct_error(VisitMethodError, self)
      end
    end

    # This module is responsible for checking all of the methods defined within
    # a given block to ensure that they are valid visit methods.
    class VisitMethodsChecker < Module
      Status = Struct.new(:checking)

      # This is the status of the checker. It's used to determine whether or not
      # we should be checking the methods that are defined. It is kept as an
      # instance variable so that it can be disabled later.
      attr_reader :status

      def initialize
        # We need the status to be an instance variable so that it can be
        # accessed by the disable! method, but also a local variable so that it
        # can be captured by the define_method block.
        status = @status = Status.new(true)

        define_method(:method_added) do |name|
          BasicVisitor.visit_method(name) if status.checking
          super(name)
        end
      end

      def disable!
        status.checking = false
      end
    end

    class << self
      # This is the list of all of the valid visit methods.
      def valid_visit_methods
        @valid_visit_methods ||=
          Visitor.instance_methods.grep(/^visit_(?!child_nodes)/)
      end

      # This method is here to help folks write visitors.
      #
      # It's not always easy to ensure you're writing the correct method name in
      # the visitor since it's perfectly valid to define methods that don't
      # override these parent methods.
      #
      # If you use this method, you can ensure you're writing the correct method
      # name. It will raise an error if the visit method you're defining isn't
      # actually a method on the parent visitor.
      def visit_method(method_name)
        return if valid_visit_methods.include?(method_name)

        raise VisitMethodError, method_name
      end

      # This method is here to help folks write visitors.
      #
      # Within the given block, every method that is defined will be checked to
      # ensure it's a valid visit method using the BasicVisitor::visit_method
      # method defined above.
      def visit_methods
        checker = VisitMethodsChecker.new
        extend(checker)
        yield
        checker.disable!
      end
    end

    def visit(node)
      node&.accept(self)
    end

    def visit_all(nodes)
      nodes.map { |node| visit(node) }
    end

    def visit_child_nodes(node)
      visit_all(node.child_nodes)
    end
  end
end
