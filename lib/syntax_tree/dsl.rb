# frozen_string_literal: true

module SyntaxTree
  # This module provides shortcuts for creating AST nodes.
  module DSL
    # Create a new BEGINBlock node.
    def BEGINBlock(lbrace, statements)
      BEGINBlock.new(
        lbrace: lbrace,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new CHAR node.
    def CHAR(value)
      CHAR.new(value: value, location: Location.default)
    end

    # Create a new ENDBlock node.
    def ENDBlock(lbrace, statements)
      ENDBlock.new(
        lbrace: lbrace,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new EndContent node.
    def EndContent(value)
      EndContent.new(value: value, location: Location.default)
    end

    # Create a new AliasNode node.
    def AliasNode(left, right)
      AliasNode.new(left: left, right: right, location: Location.default)
    end

    # Create a new ARef node.
    def ARef(collection, index)
      ARef.new(collection: collection, index: index, location: Location.default)
    end

    # Create a new ARefField node.
    def ARefField(collection, index)
      ARefField.new(
        collection: collection,
        index: index,
        location: Location.default
      )
    end

    # Create a new ArgParen node.
    def ArgParen(arguments)
      ArgParen.new(arguments: arguments, location: Location.default)
    end

    # Create a new Args node.
    def Args(parts)
      Args.new(parts: parts, location: Location.default)
    end

    # Create a new ArgBlock node.
    def ArgBlock(value)
      ArgBlock.new(value: value, location: Location.default)
    end

    # Create a new ArgStar node.
    def ArgStar(value)
      ArgStar.new(value: value, location: Location.default)
    end

    # Create a new ArgsForward node.
    def ArgsForward
      ArgsForward.new(location: Location.default)
    end

    # Create a new ArrayLiteral node.
    def ArrayLiteral(lbracket, contents)
      ArrayLiteral.new(
        lbracket: lbracket,
        contents: contents,
        location: Location.default
      )
    end

    # Create a new AryPtn node.
    def AryPtn(constant, requireds, rest, posts)
      AryPtn.new(
        constant: constant,
        requireds: requireds,
        rest: rest,
        posts: posts,
        location: Location.default
      )
    end

    # Create a new Assign node.
    def Assign(target, value)
      Assign.new(target: target, value: value, location: Location.default)
    end

    # Create a new Assoc node.
    def Assoc(key, value)
      Assoc.new(key: key, value: value, location: Location.default)
    end

    # Create a new AssocSplat node.
    def AssocSplat(value)
      AssocSplat.new(value: value, location: Location.default)
    end

    # Create a new Backref node.
    def Backref(value)
      Backref.new(value: value, location: Location.default)
    end

    # Create a new Backtick node.
    def Backtick(value)
      Backtick.new(value: value, location: Location.default)
    end

    # Create a new BareAssocHash node.
    def BareAssocHash(assocs)
      BareAssocHash.new(assocs: assocs, location: Location.default)
    end

    # Create a new Begin node.
    def Begin(bodystmt)
      Begin.new(bodystmt: bodystmt, location: Location.default)
    end

    # Create a new PinnedBegin node.
    def PinnedBegin(statement)
      PinnedBegin.new(statement: statement, location: Location.default)
    end

    # Create a new Binary node.
    def Binary(left, operator, right)
      Binary.new(
        left: left,
        operator: operator,
        right: right,
        location: Location.default
      )
    end

    # Create a new BlockVar node.
    def BlockVar(params, locals)
      BlockVar.new(params: params, locals: locals, location: Location.default)
    end

    # Create a new BlockArg node.
    def BlockArg(name)
      BlockArg.new(name: name, location: Location.default)
    end

    # Create a new BodyStmt node.
    def BodyStmt(
      statements,
      rescue_clause,
      else_keyword,
      else_clause,
      ensure_clause
    )
      BodyStmt.new(
        statements: statements,
        rescue_clause: rescue_clause,
        else_keyword: else_keyword,
        else_clause: else_clause,
        ensure_clause: ensure_clause,
        location: Location.default
      )
    end

    # Create a new Break node.
    def Break(arguments)
      Break.new(arguments: arguments, location: Location.default)
    end

    # Create a new CallNode node.
    def CallNode(receiver, operator, message, arguments)
      CallNode.new(
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        location: Location.default
      )
    end

    # Create a new Case node.
    def Case(keyword, value, consequent)
      Case.new(
        keyword: keyword,
        value: value,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new RAssign node.
    def RAssign(value, operator, pattern)
      RAssign.new(
        value: value,
        operator: operator,
        pattern: pattern,
        location: Location.default
      )
    end

    # Create a new ClassDeclaration node.
    def ClassDeclaration(
      constant,
      superclass,
      bodystmt,
      location = Location.default
    )
      ClassDeclaration.new(
        constant: constant,
        superclass: superclass,
        bodystmt: bodystmt,
        location: location
      )
    end

    # Create a new Comma node.
    def Comma(value)
      Comma.new(value: value, location: Location.default)
    end

    # Create a new Command node.
    def Command(message, arguments, block, location = Location.default)
      Command.new(
        message: message,
        arguments: arguments,
        block: block,
        location: location
      )
    end

    # Create a new CommandCall node.
    def CommandCall(receiver, operator, message, arguments, block)
      CommandCall.new(
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        block: block,
        location: Location.default
      )
    end

    # Create a new Comment node.
    def Comment(value, inline, location = Location.default)
      Comment.new(value: value, inline: inline, location: location)
    end

    # Create a new Const node.
    def Const(value)
      Const.new(value: value, location: Location.default)
    end

    # Create a new ConstPathField node.
    def ConstPathField(parent, constant)
      ConstPathField.new(
        parent: parent,
        constant: constant,
        location: Location.default
      )
    end

    # Create a new ConstPathRef node.
    def ConstPathRef(parent, constant)
      ConstPathRef.new(
        parent: parent,
        constant: constant,
        location: Location.default
      )
    end

    # Create a new ConstRef node.
    def ConstRef(constant)
      ConstRef.new(constant: constant, location: Location.default)
    end

    # Create a new CVar node.
    def CVar(value)
      CVar.new(value: value, location: Location.default)
    end

    # Create a new DefNode node.
    def DefNode(
      target,
      operator,
      name,
      params,
      bodystmt,
      location = Location.default
    )
      DefNode.new(
        target: target,
        operator: operator,
        name: name,
        params: params,
        bodystmt: bodystmt,
        location: location
      )
    end

    # Create a new Defined node.
    def Defined(value)
      Defined.new(value: value, location: Location.default)
    end

    # Create a new BlockNode node.
    def BlockNode(opening, block_var, bodystmt)
      BlockNode.new(
        opening: opening,
        block_var: block_var,
        bodystmt: bodystmt,
        location: Location.default
      )
    end

    # Create a new RangeNode node.
    def RangeNode(left, operator, right)
      RangeNode.new(
        left: left,
        operator: operator,
        right: right,
        location: Location.default
      )
    end

    # Create a new DynaSymbol node.
    def DynaSymbol(parts, quote)
      DynaSymbol.new(parts: parts, quote: quote, location: Location.default)
    end

    # Create a new Else node.
    def Else(keyword, statements)
      Else.new(
        keyword: keyword,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new Elsif node.
    def Elsif(predicate, statements, consequent)
      Elsif.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new EmbDoc node.
    def EmbDoc(value)
      EmbDoc.new(value: value, location: Location.default)
    end

    # Create a new EmbExprBeg node.
    def EmbExprBeg(value)
      EmbExprBeg.new(value: value, location: Location.default)
    end

    # Create a new EmbExprEnd node.
    def EmbExprEnd(value)
      EmbExprEnd.new(value: value, location: Location.default)
    end

    # Create a new EmbVar node.
    def EmbVar(value)
      EmbVar.new(value: value, location: Location.default)
    end

    # Create a new Ensure node.
    def Ensure(keyword, statements)
      Ensure.new(
        keyword: keyword,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new ExcessedComma node.
    def ExcessedComma(value)
      ExcessedComma.new(value: value, location: Location.default)
    end

    # Create a new Field node.
    def Field(parent, operator, name)
      Field.new(
        parent: parent,
        operator: operator,
        name: name,
        location: Location.default
      )
    end

    # Create a new FloatLiteral node.
    def FloatLiteral(value)
      FloatLiteral.new(value: value, location: Location.default)
    end

    # Create a new FndPtn node.
    def FndPtn(constant, left, values, right)
      FndPtn.new(
        constant: constant,
        left: left,
        values: values,
        right: right,
        location: Location.default
      )
    end

    # Create a new For node.
    def For(index, collection, statements)
      For.new(
        index: index,
        collection: collection,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new GVar node.
    def GVar(value)
      GVar.new(value: value, location: Location.default)
    end

    # Create a new HashLiteral node.
    def HashLiteral(lbrace, assocs)
      HashLiteral.new(
        lbrace: lbrace,
        assocs: assocs,
        location: Location.default
      )
    end

    # Create a new Heredoc node.
    def Heredoc(beginning, ending, dedent, parts)
      Heredoc.new(
        beginning: beginning,
        ending: ending,
        dedent: dedent,
        parts: parts,
        location: Location.default
      )
    end

    # Create a new HeredocBeg node.
    def HeredocBeg(value)
      HeredocBeg.new(value: value, location: Location.default)
    end

    # Create a new HeredocEnd node.
    def HeredocEnd(value)
      HeredocEnd.new(value: value, location: Location.default)
    end

    # Create a new HshPtn node.
    def HshPtn(constant, keywords, keyword_rest)
      HshPtn.new(
        constant: constant,
        keywords: keywords,
        keyword_rest: keyword_rest,
        location: Location.default
      )
    end

    # Create a new Ident node.
    def Ident(value)
      Ident.new(value: value, location: Location.default)
    end

    # Create a new IfNode node.
    def IfNode(predicate, statements, consequent)
      IfNode.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new IfOp node.
    def IfOp(predicate, truthy, falsy)
      IfOp.new(
        predicate: predicate,
        truthy: truthy,
        falsy: falsy,
        location: Location.default
      )
    end

    # Create a new Imaginary node.
    def Imaginary(value)
      Imaginary.new(value: value, location: Location.default)
    end

    # Create a new In node.
    def In(pattern, statements, consequent)
      In.new(
        pattern: pattern,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new Int node.
    def Int(value)
      Int.new(value: value, location: Location.default)
    end

    # Create a new IVar node.
    def IVar(value)
      IVar.new(value: value, location: Location.default)
    end

    # Create a new Kw node.
    def Kw(value)
      Kw.new(value: value, location: Location.default)
    end

    # Create a new KwRestParam node.
    def KwRestParam(name)
      KwRestParam.new(name: name, location: Location.default)
    end

    # Create a new Label node.
    def Label(value)
      Label.new(value: value, location: Location.default)
    end

    # Create a new LabelEnd node.
    def LabelEnd(value)
      LabelEnd.new(value: value, location: Location.default)
    end

    # Create a new Lambda node.
    def Lambda(params, statements)
      Lambda.new(
        params: params,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new LambdaVar node.
    def LambdaVar(params, locals)
      LambdaVar.new(params: params, locals: locals, location: Location.default)
    end

    # Create a new LBrace node.
    def LBrace(value)
      LBrace.new(value: value, location: Location.default)
    end

    # Create a new LBracket node.
    def LBracket(value)
      LBracket.new(value: value, location: Location.default)
    end

    # Create a new LParen node.
    def LParen(value)
      LParen.new(value: value, location: Location.default)
    end

    # Create a new MAssign node.
    def MAssign(target, value)
      MAssign.new(target: target, value: value, location: Location.default)
    end

    # Create a new MethodAddBlock node.
    def MethodAddBlock(call, block, location = Location.default)
      MethodAddBlock.new(call: call, block: block, location: location)
    end

    # Create a new MLHS node.
    def MLHS(parts, comma)
      MLHS.new(parts: parts, comma: comma, location: Location.default)
    end

    # Create a new MLHSParen node.
    def MLHSParen(contents, comma)
      MLHSParen.new(
        contents: contents,
        comma: comma,
        location: Location.default
      )
    end

    # Create a new ModuleDeclaration node.
    def ModuleDeclaration(constant, bodystmt)
      ModuleDeclaration.new(
        constant: constant,
        bodystmt: bodystmt,
        location: Location.default
      )
    end

    # Create a new MRHS node.
    def MRHS(parts)
      MRHS.new(parts: parts, location: Location.default)
    end

    # Create a new Next node.
    def Next(arguments)
      Next.new(arguments: arguments, location: Location.default)
    end

    # Create a new Op node.
    def Op(value)
      Op.new(value: value, location: Location.default)
    end

    # Create a new OpAssign node.
    def OpAssign(target, operator, value)
      OpAssign.new(
        target: target,
        operator: operator,
        value: value,
        location: Location.default
      )
    end

    # Create a new Params node.
    def Params(requireds, optionals, rest, posts, keywords, keyword_rest, block)
      Params.new(
        requireds: requireds,
        optionals: optionals,
        rest: rest,
        posts: posts,
        keywords: keywords,
        keyword_rest: keyword_rest,
        block: block,
        location: Location.default
      )
    end

    # Create a new Paren node.
    def Paren(lparen, contents)
      Paren.new(lparen: lparen, contents: contents, location: Location.default)
    end

    # Create a new Period node.
    def Period(value)
      Period.new(value: value, location: Location.default)
    end

    # Create a new Program node.
    def Program(statements)
      Program.new(statements: statements, location: Location.default)
    end

    # Create a new QSymbols node.
    def QSymbols(beginning, elements)
      QSymbols.new(
        beginning: beginning,
        elements: elements,
        location: Location.default
      )
    end

    # Create a new QSymbolsBeg node.
    def QSymbolsBeg(value)
      QSymbolsBeg.new(value: value, location: Location.default)
    end

    # Create a new QWords node.
    def QWords(beginning, elements)
      QWords.new(
        beginning: beginning,
        elements: elements,
        location: Location.default
      )
    end

    # Create a new QWordsBeg node.
    def QWordsBeg(value)
      QWordsBeg.new(value: value, location: Location.default)
    end

    # Create a new RationalLiteral node.
    def RationalLiteral(value)
      RationalLiteral.new(value: value, location: Location.default)
    end

    # Create a new RBrace node.
    def RBrace(value)
      RBrace.new(value: value, location: Location.default)
    end

    # Create a new RBracket node.
    def RBracket(value)
      RBracket.new(value: value, location: Location.default)
    end

    # Create a new Redo node.
    def Redo
      Redo.new(location: Location.default)
    end

    # Create a new RegexpContent node.
    def RegexpContent(beginning, parts)
      RegexpContent.new(
        beginning: beginning,
        parts: parts,
        location: Location.default
      )
    end

    # Create a new RegexpBeg node.
    def RegexpBeg(value)
      RegexpBeg.new(value: value, location: Location.default)
    end

    # Create a new RegexpEnd node.
    def RegexpEnd(value)
      RegexpEnd.new(value: value, location: Location.default)
    end

    # Create a new RegexpLiteral node.
    def RegexpLiteral(beginning, ending, parts)
      RegexpLiteral.new(
        beginning: beginning,
        ending: ending,
        parts: parts,
        location: Location.default
      )
    end

    # Create a new RescueEx node.
    def RescueEx(exceptions, variable)
      RescueEx.new(
        exceptions: exceptions,
        variable: variable,
        location: Location.default
      )
    end

    # Create a new Rescue node.
    def Rescue(keyword, exception, statements, consequent)
      Rescue.new(
        keyword: keyword,
        exception: exception,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new RescueMod node.
    def RescueMod(statement, value)
      RescueMod.new(
        statement: statement,
        value: value,
        location: Location.default
      )
    end

    # Create a new RestParam node.
    def RestParam(name)
      RestParam.new(name: name, location: Location.default)
    end

    # Create a new Retry node.
    def Retry
      Retry.new(location: Location.default)
    end

    # Create a new ReturnNode node.
    def ReturnNode(arguments)
      ReturnNode.new(arguments: arguments, location: Location.default)
    end

    # Create a new RParen node.
    def RParen(value)
      RParen.new(value: value, location: Location.default)
    end

    # Create a new SClass node.
    def SClass(target, bodystmt)
      SClass.new(target: target, bodystmt: bodystmt, location: Location.default)
    end

    # Create a new Statements node.
    def Statements(body)
      Statements.new(body: body, location: Location.default)
    end

    # Create a new StringContent node.
    def StringContent(parts)
      StringContent.new(parts: parts, location: Location.default)
    end

    # Create a new StringConcat node.
    def StringConcat(left, right)
      StringConcat.new(left: left, right: right, location: Location.default)
    end

    # Create a new StringDVar node.
    def StringDVar(variable)
      StringDVar.new(variable: variable, location: Location.default)
    end

    # Create a new StringEmbExpr node.
    def StringEmbExpr(statements)
      StringEmbExpr.new(statements: statements, location: Location.default)
    end

    # Create a new StringLiteral node.
    def StringLiteral(parts, quote)
      StringLiteral.new(parts: parts, quote: quote, location: Location.default)
    end

    # Create a new Super node.
    def Super(arguments)
      Super.new(arguments: arguments, location: Location.default)
    end

    # Create a new SymBeg node.
    def SymBeg(value)
      SymBeg.new(value: value, location: Location.default)
    end

    # Create a new SymbolContent node.
    def SymbolContent(value)
      SymbolContent.new(value: value, location: Location.default)
    end

    # Create a new SymbolLiteral node.
    def SymbolLiteral(value)
      SymbolLiteral.new(value: value, location: Location.default)
    end

    # Create a new Symbols node.
    def Symbols(beginning, elements)
      Symbols.new(
        beginning: beginning,
        elements: elements,
        location: Location.default
      )
    end

    # Create a new SymbolsBeg node.
    def SymbolsBeg(value)
      SymbolsBeg.new(value: value, location: Location.default)
    end

    # Create a new TLambda node.
    def TLambda(value)
      TLambda.new(value: value, location: Location.default)
    end

    # Create a new TLamBeg node.
    def TLamBeg(value)
      TLamBeg.new(value: value, location: Location.default)
    end

    # Create a new TopConstField node.
    def TopConstField(constant)
      TopConstField.new(constant: constant, location: Location.default)
    end

    # Create a new TopConstRef node.
    def TopConstRef(constant)
      TopConstRef.new(constant: constant, location: Location.default)
    end

    # Create a new TStringBeg node.
    def TStringBeg(value)
      TStringBeg.new(value: value, location: Location.default)
    end

    # Create a new TStringContent node.
    def TStringContent(value)
      TStringContent.new(value: value, location: Location.default)
    end

    # Create a new TStringEnd node.
    def TStringEnd(value)
      TStringEnd.new(value: value, location: Location.default)
    end

    # Create a new Not node.
    def Not(statement, parentheses)
      Not.new(
        statement: statement,
        parentheses: parentheses,
        location: Location.default
      )
    end

    # Create a new Unary node.
    def Unary(operator, statement)
      Unary.new(
        operator: operator,
        statement: statement,
        location: Location.default
      )
    end

    # Create a new Undef node.
    def Undef(symbols)
      Undef.new(symbols: symbols, location: Location.default)
    end

    # Create a new UnlessNode node.
    def UnlessNode(predicate, statements, consequent)
      UnlessNode.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new UntilNode node.
    def UntilNode(predicate, statements)
      UntilNode.new(
        predicate: predicate,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new VarField node.
    def VarField(value)
      VarField.new(value: value, location: Location.default)
    end

    # Create a new VarRef node.
    def VarRef(value)
      VarRef.new(value: value, location: Location.default)
    end

    # Create a new PinnedVarRef node.
    def PinnedVarRef(value)
      PinnedVarRef.new(value: value, location: Location.default)
    end

    # Create a new VCall node.
    def VCall(value)
      VCall.new(value: value, location: Location.default)
    end

    # Create a new VoidStmt node.
    def VoidStmt
      VoidStmt.new(location: Location.default)
    end

    # Create a new When node.
    def When(arguments, statements, consequent)
      When.new(
        arguments: arguments,
        statements: statements,
        consequent: consequent,
        location: Location.default
      )
    end

    # Create a new WhileNode node.
    def WhileNode(predicate, statements)
      WhileNode.new(
        predicate: predicate,
        statements: statements,
        location: Location.default
      )
    end

    # Create a new Word node.
    def Word(parts)
      Word.new(parts: parts, location: Location.default)
    end

    # Create a new Words node.
    def Words(beginning, elements)
      Words.new(
        beginning: beginning,
        elements: elements,
        location: Location.default
      )
    end

    # Create a new WordsBeg node.
    def WordsBeg(value)
      WordsBeg.new(value: value, location: Location.default)
    end

    # Create a new XString node.
    def XString(parts)
      XString.new(parts: parts, location: Location.default)
    end

    # Create a new XStringLiteral node.
    def XStringLiteral(parts)
      XStringLiteral.new(parts: parts, location: Location.default)
    end

    # Create a new YieldNode node.
    def YieldNode(arguments)
      YieldNode.new(arguments: arguments, location: Location.default)
    end

    # Create a new ZSuper node.
    def ZSuper
      ZSuper.new(location: Location.default)
    end
  end
end
