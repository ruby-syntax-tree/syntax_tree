# frozen_string_literal: true

module SyntaxTree
  # This visitor walks through the tree and copies each node as it is being
  # visited. This is useful for mutating the tree before it is formatted.
  class MutationVisitor < BasicVisitor
    attr_reader :mutations

    def initialize
      @mutations = []
    end

    # Create a new mutation based on the given query that will mutate the node
    # using the given block. The block should return a new node that will take
    # the place of the given node in the tree. These blocks frequently make use
    # of the `copy` method on nodes to create a new node with the same
    # properties as the original node.
    def mutate(query, &block)
      mutations << [Pattern.new(query).compile, block]
    end

    # This is the base visit method for each node in the tree. It first creates
    # a copy of the node using the visit_* methods defined below. Then it checks
    # each mutation in sequence and calls it if it finds a match.
    def visit(node)
      return unless node
      result = node.accept(self)

      mutations.each do |(pattern, mutation)|
        result = mutation.call(result) if pattern.call(result)
      end

      result
    end

    visit_methods do
      # Visit a BEGINBlock node.
      def visit_BEGIN(node)
        node.copy(
          lbrace: visit(node.lbrace),
          statements: visit(node.statements)
        )
      end

      # Visit a CHAR node.
      def visit_CHAR(node)
        node.copy
      end

      # Visit a ENDBlock node.
      def visit_END(node)
        node.copy(
          lbrace: visit(node.lbrace),
          statements: visit(node.statements)
        )
      end

      # Visit a EndContent node.
      def visit___end__(node)
        node.copy
      end

      # Visit a AliasNode node.
      def visit_alias(node)
        node.copy(left: visit(node.left), right: visit(node.right))
      end

      # Visit a ARef node.
      def visit_aref(node)
        node.copy(index: visit(node.index))
      end

      # Visit a ARefField node.
      def visit_aref_field(node)
        node.copy(index: visit(node.index))
      end

      # Visit a ArgParen node.
      def visit_arg_paren(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a Args node.
      def visit_args(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a ArgBlock node.
      def visit_arg_block(node)
        node.copy(value: visit(node.value))
      end

      # Visit a ArgStar node.
      def visit_arg_star(node)
        node.copy(value: visit(node.value))
      end

      # Visit a ArgsForward node.
      def visit_args_forward(node)
        node.copy
      end

      # Visit a ArrayLiteral node.
      def visit_array(node)
        node.copy(
          lbracket: visit(node.lbracket),
          contents: visit(node.contents)
        )
      end

      # Visit a AryPtn node.
      def visit_aryptn(node)
        node.copy(
          constant: visit(node.constant),
          requireds: visit_all(node.requireds),
          rest: visit(node.rest),
          posts: visit_all(node.posts)
        )
      end

      # Visit a Assign node.
      def visit_assign(node)
        node.copy(target: visit(node.target))
      end

      # Visit a Assoc node.
      def visit_assoc(node)
        node.copy
      end

      # Visit a AssocSplat node.
      def visit_assoc_splat(node)
        node.copy
      end

      # Visit a Backref node.
      def visit_backref(node)
        node.copy
      end

      # Visit a Backtick node.
      def visit_backtick(node)
        node.copy
      end

      # Visit a BareAssocHash node.
      def visit_bare_assoc_hash(node)
        node.copy(assocs: visit_all(node.assocs))
      end

      # Visit a Begin node.
      def visit_begin(node)
        node.copy(bodystmt: visit(node.bodystmt))
      end

      # Visit a PinnedBegin node.
      def visit_pinned_begin(node)
        node.copy
      end

      # Visit a Binary node.
      def visit_binary(node)
        node.copy
      end

      # Visit a BlockVar node.
      def visit_block_var(node)
        node.copy(params: visit(node.params), locals: visit_all(node.locals))
      end

      # Visit a BlockArg node.
      def visit_blockarg(node)
        node.copy(name: visit(node.name))
      end

      # Visit a BodyStmt node.
      def visit_bodystmt(node)
        node.copy(
          statements: visit(node.statements),
          rescue_clause: visit(node.rescue_clause),
          else_clause: visit(node.else_clause),
          ensure_clause: visit(node.ensure_clause)
        )
      end

      # Visit a Break node.
      def visit_break(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a Call node.
      def visit_call(node)
        node.copy(
          receiver: visit(node.receiver),
          operator: node.operator == :"::" ? :"::" : visit(node.operator),
          message: node.message == :call ? :call : visit(node.message),
          arguments: visit(node.arguments)
        )
      end

      # Visit a Case node.
      def visit_case(node)
        node.copy(
          keyword: visit(node.keyword),
          value: visit(node.value),
          consequent: visit(node.consequent)
        )
      end

      # Visit a RAssign node.
      def visit_rassign(node)
        node.copy(operator: visit(node.operator))
      end

      # Visit a ClassDeclaration node.
      def visit_class(node)
        node.copy(
          constant: visit(node.constant),
          superclass: visit(node.superclass),
          bodystmt: visit(node.bodystmt)
        )
      end

      # Visit a Comma node.
      def visit_comma(node)
        node.copy
      end

      # Visit a Command node.
      def visit_command(node)
        node.copy(
          message: visit(node.message),
          arguments: visit(node.arguments),
          block: visit(node.block)
        )
      end

      # Visit a CommandCall node.
      def visit_command_call(node)
        node.copy(
          operator: node.operator == :"::" ? :"::" : visit(node.operator),
          message: visit(node.message),
          arguments: visit(node.arguments),
          block: visit(node.block)
        )
      end

      # Visit a Comment node.
      def visit_comment(node)
        node.copy
      end

      # Visit a Const node.
      def visit_const(node)
        node.copy
      end

      # Visit a ConstPathField node.
      def visit_const_path_field(node)
        node.copy(constant: visit(node.constant))
      end

      # Visit a ConstPathRef node.
      def visit_const_path_ref(node)
        node.copy(constant: visit(node.constant))
      end

      # Visit a ConstRef node.
      def visit_const_ref(node)
        node.copy(constant: visit(node.constant))
      end

      # Visit a CVar node.
      def visit_cvar(node)
        node.copy
      end

      # Visit a Def node.
      def visit_def(node)
        node.copy(
          target: visit(node.target),
          operator: visit(node.operator),
          name: visit(node.name),
          params: visit(node.params),
          bodystmt: visit(node.bodystmt)
        )
      end

      # Visit a Defined node.
      def visit_defined(node)
        node.copy
      end

      # Visit a Block node.
      def visit_block(node)
        node.copy(
          opening: visit(node.opening),
          block_var: visit(node.block_var),
          bodystmt: visit(node.bodystmt)
        )
      end

      # Visit a RangeNode node.
      def visit_range(node)
        node.copy(
          left: visit(node.left),
          operator: visit(node.operator),
          right: visit(node.right)
        )
      end

      # Visit a DynaSymbol node.
      def visit_dyna_symbol(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a Else node.
      def visit_else(node)
        node.copy(
          keyword: visit(node.keyword),
          statements: visit(node.statements)
        )
      end

      # Visit a Elsif node.
      def visit_elsif(node)
        node.copy(
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a EmbDoc node.
      def visit_embdoc(node)
        node.copy
      end

      # Visit a EmbExprBeg node.
      def visit_embexpr_beg(node)
        node.copy
      end

      # Visit a EmbExprEnd node.
      def visit_embexpr_end(node)
        node.copy
      end

      # Visit a EmbVar node.
      def visit_embvar(node)
        node.copy
      end

      # Visit a Ensure node.
      def visit_ensure(node)
        node.copy(
          keyword: visit(node.keyword),
          statements: visit(node.statements)
        )
      end

      # Visit a ExcessedComma node.
      def visit_excessed_comma(node)
        node.copy
      end

      # Visit a Field node.
      def visit_field(node)
        node.copy(
          operator: node.operator == :"::" ? :"::" : visit(node.operator),
          name: visit(node.name)
        )
      end

      # Visit a FloatLiteral node.
      def visit_float(node)
        node.copy
      end

      # Visit a FndPtn node.
      def visit_fndptn(node)
        node.copy(
          constant: visit(node.constant),
          left: visit(node.left),
          values: visit_all(node.values),
          right: visit(node.right)
        )
      end

      # Visit a For node.
      def visit_for(node)
        node.copy(index: visit(node.index), statements: visit(node.statements))
      end

      # Visit a GVar node.
      def visit_gvar(node)
        node.copy
      end

      # Visit a HashLiteral node.
      def visit_hash(node)
        node.copy(lbrace: visit(node.lbrace), assocs: visit_all(node.assocs))
      end

      # Visit a Heredoc node.
      def visit_heredoc(node)
        node.copy(
          beginning: visit(node.beginning),
          ending: visit(node.ending),
          parts: visit_all(node.parts)
        )
      end

      # Visit a HeredocBeg node.
      def visit_heredoc_beg(node)
        node.copy
      end

      # Visit a HeredocEnd node.
      def visit_heredoc_end(node)
        node.copy
      end

      # Visit a HshPtn node.
      def visit_hshptn(node)
        node.copy(
          constant: visit(node.constant),
          keywords:
            node.keywords.map { |label, value| [visit(label), visit(value)] },
          keyword_rest: visit(node.keyword_rest)
        )
      end

      # Visit a Ident node.
      def visit_ident(node)
        node.copy
      end

      # Visit a IfNode node.
      def visit_if(node)
        node.copy(
          predicate: visit(node.predicate),
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a IfOp node.
      def visit_if_op(node)
        node.copy
      end

      # Visit a Imaginary node.
      def visit_imaginary(node)
        node.copy
      end

      # Visit a In node.
      def visit_in(node)
        node.copy(
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a Int node.
      def visit_int(node)
        node.copy
      end

      # Visit a IVar node.
      def visit_ivar(node)
        node.copy
      end

      # Visit a Kw node.
      def visit_kw(node)
        node.copy
      end

      # Visit a KwRestParam node.
      def visit_kwrest_param(node)
        node.copy(name: visit(node.name))
      end

      # Visit a Label node.
      def visit_label(node)
        node.copy
      end

      # Visit a LabelEnd node.
      def visit_label_end(node)
        node.copy
      end

      # Visit a Lambda node.
      def visit_lambda(node)
        node.copy(
          params: visit(node.params),
          statements: visit(node.statements)
        )
      end

      # Visit a LambdaVar node.
      def visit_lambda_var(node)
        node.copy(params: visit(node.params), locals: visit_all(node.locals))
      end

      # Visit a LBrace node.
      def visit_lbrace(node)
        node.copy
      end

      # Visit a LBracket node.
      def visit_lbracket(node)
        node.copy
      end

      # Visit a LParen node.
      def visit_lparen(node)
        node.copy
      end

      # Visit a MAssign node.
      def visit_massign(node)
        node.copy(target: visit(node.target))
      end

      # Visit a MethodAddBlock node.
      def visit_method_add_block(node)
        node.copy(call: visit(node.call), block: visit(node.block))
      end

      # Visit a MLHS node.
      def visit_mlhs(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a MLHSParen node.
      def visit_mlhs_paren(node)
        node.copy(contents: visit(node.contents))
      end

      # Visit a ModuleDeclaration node.
      def visit_module(node)
        node.copy(
          constant: visit(node.constant),
          bodystmt: visit(node.bodystmt)
        )
      end

      # Visit a MRHS node.
      def visit_mrhs(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a Next node.
      def visit_next(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a Op node.
      def visit_op(node)
        node.copy
      end

      # Visit a OpAssign node.
      def visit_opassign(node)
        node.copy(target: visit(node.target), operator: visit(node.operator))
      end

      # Visit a Params node.
      def visit_params(node)
        node.copy(
          requireds: visit_all(node.requireds),
          optionals:
            node.optionals.map { |ident, value| [visit(ident), visit(value)] },
          rest: visit(node.rest),
          posts: visit_all(node.posts),
          keywords:
            node.keywords.map { |ident, value| [visit(ident), visit(value)] },
          keyword_rest:
            node.keyword_rest == :nil ? :nil : visit(node.keyword_rest),
          block: visit(node.block)
        )
      end

      # Visit a Paren node.
      def visit_paren(node)
        node.copy(lparen: visit(node.lparen), contents: visit(node.contents))
      end

      # Visit a Period node.
      def visit_period(node)
        node.copy
      end

      # Visit a Program node.
      def visit_program(node)
        node.copy(statements: visit(node.statements))
      end

      # Visit a QSymbols node.
      def visit_qsymbols(node)
        node.copy(
          beginning: visit(node.beginning),
          elements: visit_all(node.elements)
        )
      end

      # Visit a QSymbolsBeg node.
      def visit_qsymbols_beg(node)
        node.copy
      end

      # Visit a QWords node.
      def visit_qwords(node)
        node.copy(
          beginning: visit(node.beginning),
          elements: visit_all(node.elements)
        )
      end

      # Visit a QWordsBeg node.
      def visit_qwords_beg(node)
        node.copy
      end

      # Visit a RationalLiteral node.
      def visit_rational(node)
        node.copy
      end

      # Visit a RBrace node.
      def visit_rbrace(node)
        node.copy
      end

      # Visit a RBracket node.
      def visit_rbracket(node)
        node.copy
      end

      # Visit a Redo node.
      def visit_redo(node)
        node.copy
      end

      # Visit a RegexpContent node.
      def visit_regexp_content(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a RegexpBeg node.
      def visit_regexp_beg(node)
        node.copy
      end

      # Visit a RegexpEnd node.
      def visit_regexp_end(node)
        node.copy
      end

      # Visit a RegexpLiteral node.
      def visit_regexp_literal(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a RescueEx node.
      def visit_rescue_ex(node)
        node.copy(variable: visit(node.variable))
      end

      # Visit a Rescue node.
      def visit_rescue(node)
        node.copy(
          keyword: visit(node.keyword),
          exception: visit(node.exception),
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a RescueMod node.
      def visit_rescue_mod(node)
        node.copy
      end

      # Visit a RestParam node.
      def visit_rest_param(node)
        node.copy(name: visit(node.name))
      end

      # Visit a Retry node.
      def visit_retry(node)
        node.copy
      end

      # Visit a Return node.
      def visit_return(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a RParen node.
      def visit_rparen(node)
        node.copy
      end

      # Visit a SClass node.
      def visit_sclass(node)
        node.copy(bodystmt: visit(node.bodystmt))
      end

      # Visit a Statements node.
      def visit_statements(node)
        node.copy(body: visit_all(node.body))
      end

      # Visit a StringContent node.
      def visit_string_content(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a StringConcat node.
      def visit_string_concat(node)
        node.copy(left: visit(node.left), right: visit(node.right))
      end

      # Visit a StringDVar node.
      def visit_string_dvar(node)
        node.copy(variable: visit(node.variable))
      end

      # Visit a StringEmbExpr node.
      def visit_string_embexpr(node)
        node.copy(statements: visit(node.statements))
      end

      # Visit a StringLiteral node.
      def visit_string_literal(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a Super node.
      def visit_super(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a SymBeg node.
      def visit_symbeg(node)
        node.copy
      end

      # Visit a SymbolContent node.
      def visit_symbol_content(node)
        node.copy(value: visit(node.value))
      end

      # Visit a SymbolLiteral node.
      def visit_symbol_literal(node)
        node.copy(value: visit(node.value))
      end

      # Visit a Symbols node.
      def visit_symbols(node)
        node.copy(
          beginning: visit(node.beginning),
          elements: visit_all(node.elements)
        )
      end

      # Visit a SymbolsBeg node.
      def visit_symbols_beg(node)
        node.copy
      end

      # Visit a TLambda node.
      def visit_tlambda(node)
        node.copy
      end

      # Visit a TLamBeg node.
      def visit_tlambeg(node)
        node.copy
      end

      # Visit a TopConstField node.
      def visit_top_const_field(node)
        node.copy(constant: visit(node.constant))
      end

      # Visit a TopConstRef node.
      def visit_top_const_ref(node)
        node.copy(constant: visit(node.constant))
      end

      # Visit a TStringBeg node.
      def visit_tstring_beg(node)
        node.copy
      end

      # Visit a TStringContent node.
      def visit_tstring_content(node)
        node.copy
      end

      # Visit a TStringEnd node.
      def visit_tstring_end(node)
        node.copy
      end

      # Visit a Not node.
      def visit_not(node)
        node.copy(statement: visit(node.statement))
      end

      # Visit a Unary node.
      def visit_unary(node)
        node.copy
      end

      # Visit a Undef node.
      def visit_undef(node)
        node.copy(symbols: visit_all(node.symbols))
      end

      # Visit a UnlessNode node.
      def visit_unless(node)
        node.copy(
          predicate: visit(node.predicate),
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a UntilNode node.
      def visit_until(node)
        node.copy(
          predicate: visit(node.predicate),
          statements: visit(node.statements)
        )
      end

      # Visit a VarField node.
      def visit_var_field(node)
        node.copy(value: visit(node.value))
      end

      # Visit a VarRef node.
      def visit_var_ref(node)
        node.copy(value: visit(node.value))
      end

      # Visit a PinnedVarRef node.
      def visit_pinned_var_ref(node)
        node.copy(value: visit(node.value))
      end

      # Visit a VCall node.
      def visit_vcall(node)
        node.copy(value: visit(node.value))
      end

      # Visit a VoidStmt node.
      def visit_void_stmt(node)
        node.copy
      end

      # Visit a When node.
      def visit_when(node)
        node.copy(
          arguments: visit(node.arguments),
          statements: visit(node.statements),
          consequent: visit(node.consequent)
        )
      end

      # Visit a WhileNode node.
      def visit_while(node)
        node.copy(
          predicate: visit(node.predicate),
          statements: visit(node.statements)
        )
      end

      # Visit a Word node.
      def visit_word(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a Words node.
      def visit_words(node)
        node.copy(
          beginning: visit(node.beginning),
          elements: visit_all(node.elements)
        )
      end

      # Visit a WordsBeg node.
      def visit_words_beg(node)
        node.copy
      end

      # Visit a XString node.
      def visit_xstring(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a XStringLiteral node.
      def visit_xstring_literal(node)
        node.copy(parts: visit_all(node.parts))
      end

      # Visit a YieldNode node.
      def visit_yield(node)
        node.copy(arguments: visit(node.arguments))
      end

      # Visit a ZSuper node.
      def visit_zsuper(node)
        node.copy
      end
    end
  end
end
