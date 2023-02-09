# frozen_string_literal: true

module SyntaxTree
  module Translation
    # This visitor is responsible for converting the syntax tree produced by
    # Syntax Tree into the syntax tree produced by the rubocop/rubocop-ast gem.
    class RuboCopAST < Parser
      private

      # This method is effectively the same thing as the parser gem except that
      # it uses the rubocop-ast specializations of the nodes.
      def s(type, children, location)
        ::RuboCop::AST::Builder::NODE_MAP.fetch(type, ::RuboCop::AST::Node).new(
          type,
          children,
          location: location
        )
      end
    end
  end
end
