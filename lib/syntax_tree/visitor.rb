# frozen_string_literal: true

module SyntaxTree
  class Visitor
    def visit_all(nodes)
      nodes.each do |node|
        visit(node)
      end
    end

    def visit(node)
      node&.accept(self)
    end
  end
end
