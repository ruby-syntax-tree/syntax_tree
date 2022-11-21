# frozen_string_literal: true

module SyntaxTree
  module DSL
    def ARef(collection, index)
      ARef.new(collection: collection, index: index, location: Location.default)
    end

    def ARefField(collection, index)
      ARefField.new(collection: collection, index: index, location: Location.default)
    end

    def Args(parts)
      Args.new(parts: parts, location: Location.default)
    end

    def ArgParen(arguments)
      ArgParen.new(arguments: arguments, location: Location.default)
    end

    def Assign(target, value)
      Assign.new(target: target, value: value, location: Location.default)
    end

    def Assoc(key, value)
      Assoc.new(key: key, value: value, location: Location.default)
    end

    def Binary(left, operator, right)
      Binary.new(left: left, operator: operator, right: right, location: Location.default)
    end

    def BlockNode(opening, block_var, bodystmt)
      BlockNode.new(opening: opening, block_var: block_var, bodystmt: bodystmt, location: Location.default)
    end

    def BodyStmt(statements, rescue_clause, else_keyword, else_clause, ensure_clause)
      BodyStmt.new(statements: statements, rescue_clause: rescue_clause, else_keyword: else_keyword, else_clause: else_clause, ensure_clause: ensure_clause, location: Location.default)
    end

    def CallNode(receiver, operator, message, arguments)
      CallNode.new(receiver: receiver, operator: operator, message: message, arguments: arguments, location: Location.default)
    end

    def Case(keyword, value, consequent)
      Case.new(keyword: keyword, value: value, consequent: consequent, location: Location.default)
    end

    def FloatLiteral(value)
      FloatLiteral.new(value: value, location: Location.default)
    end

    def GVar(value)
      GVar.new(value: value, location: Location.default)
    end

    def HashLiteral(lbrace, assocs)
      HashLiteral.new(lbrace: lbrace, assocs: assocs, location: Location.default)
    end

    def Ident(value)
      Ident.new(value: value, location: Location.default)
    end

    def IfNode(predicate, statements, consequent)
      IfNode.new(predicate: predicate, statements: statements, consequent: consequent, location: Location.default)
    end

    def Int(value)
      Int.new(value: value, location: Location.default)
    end

    def Kw(value)
      Kw.new(value: value, location: Location.default)
    end

    def LBrace(value)
      LBrace.new(value: value, location: Location.default)
    end

    def MethodAddBlock(call, block)
      MethodAddBlock.new(call: call, block: block, location: Location.default)
    end

    def Next(arguments)
      Next.new(arguments: arguments, location: Location.default)
    end

    def Op(value)
      Op.new(value: value, location: Location.default)
    end

    def OpAssign(target, operator, value)
      OpAssign.new(target: target, operator: operator, value: value, location: Location.default)
    end

    def Period(value)
      Period.new(value: value, location: Location.default)
    end

    def Program(statements)
      Program.new(statements: statements, location: Location.default)
    end

    def ReturnNode(arguments)
      ReturnNode.new(arguments: arguments, location: Location.default)
    end

    def Statements(body)
      Statements.new(nil, body: body, location: Location.default)
    end

    def SymbolLiteral(value)
      SymbolLiteral.new(value: value, location: Location.default)
    end

    def VarField(value)
      VarField.new(value: value, location: Location.default)
    end

    def VarRef(value)
      VarRef.new(value: value, location: Location.default)
    end

    def When(arguments, statements, consequent)
      When.new(arguments: arguments, statements: statements, consequent: consequent, location: Location.default)
    end
  end
end
