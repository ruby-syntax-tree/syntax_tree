# frozen_string_literal: true

module SyntaxTree
  # Visitor is a parent class that provides the ability to walk down the tree
  # and handle a subset of nodes. By defining your own subclass, you can
  # explicitly handle a node type by defining a visit_* method.
  class Visitor < BasicVisitor
    # Visit an ARef node.
    alias visit_aref visit_child_nodes

    # Visit an ARefField node.
    alias visit_aref_field visit_child_nodes

    # Visit an AliasNode node.
    alias visit_alias visit_child_nodes

    # Visit an ArgBlock node.
    alias visit_arg_block visit_child_nodes

    # Visit an ArgParen node.
    alias visit_arg_paren visit_child_nodes

    # Visit an ArgStar node.
    alias visit_arg_star visit_child_nodes

    # Visit an Args node.
    alias visit_args visit_child_nodes

    # Visit an ArgsForward node.
    alias visit_args_forward visit_child_nodes

    # Visit an ArrayLiteral node.
    alias visit_array visit_child_nodes

    # Visit an AryPtn node.
    alias visit_aryptn visit_child_nodes

    # Visit an Assign node.
    alias visit_assign visit_child_nodes

    # Visit an Assoc node.
    alias visit_assoc visit_child_nodes

    # Visit an AssocSplat node.
    alias visit_assoc_splat visit_child_nodes

    # Visit a Backref node.
    alias visit_backref visit_child_nodes

    # Visit a Backtick node.
    alias visit_backtick visit_child_nodes

    # Visit a BareAssocHash node.
    alias visit_bare_assoc_hash visit_child_nodes

    # Visit a BEGINBlock node.
    alias visit_BEGIN visit_child_nodes

    # Visit a Begin node.
    alias visit_begin visit_child_nodes

    # Visit a Binary node.
    alias visit_binary visit_child_nodes

    # Visit a Block node.
    alias visit_block visit_child_nodes

    # Visit a BlockArg node.
    alias visit_blockarg visit_child_nodes

    # Visit a BlockVar node.
    alias visit_block_var visit_child_nodes

    # Visit a BodyStmt node.
    alias visit_bodystmt visit_child_nodes

    # Visit a Break node.
    alias visit_break visit_child_nodes

    # Visit a Call node.
    alias visit_call visit_child_nodes

    # Visit a Case node.
    alias visit_case visit_child_nodes

    # Visit a CHAR node.
    alias visit_CHAR visit_child_nodes

    # Visit a ClassDeclaration node.
    alias visit_class visit_child_nodes

    # Visit a Comma node.
    alias visit_comma visit_child_nodes

    # Visit a Command node.
    alias visit_command visit_child_nodes

    # Visit a CommandCall node.
    alias visit_command_call visit_child_nodes

    # Visit a Comment node.
    alias visit_comment visit_child_nodes

    # Visit a Const node.
    alias visit_const visit_child_nodes

    # Visit a ConstPathField node.
    alias visit_const_path_field visit_child_nodes

    # Visit a ConstPathRef node.
    alias visit_const_path_ref visit_child_nodes

    # Visit a ConstRef node.
    alias visit_const_ref visit_child_nodes

    # Visit a CVar node.
    alias visit_cvar visit_child_nodes

    # Visit a Def node.
    alias visit_def visit_child_nodes

    # Visit a Defined node.
    alias visit_defined visit_child_nodes

    # Visit a DynaSymbol node.
    alias visit_dyna_symbol visit_child_nodes

    # Visit an ENDBlock node.
    alias visit_END visit_child_nodes

    # Visit an Else node.
    alias visit_else visit_child_nodes

    # Visit an Elsif node.
    alias visit_elsif visit_child_nodes

    # Visit an EmbDoc node.
    alias visit_embdoc visit_child_nodes

    # Visit an EmbExprBeg node.
    alias visit_embexpr_beg visit_child_nodes

    # Visit an EmbExprEnd node.
    alias visit_embexpr_end visit_child_nodes

    # Visit an EmbVar node.
    alias visit_embvar visit_child_nodes

    # Visit an Ensure node.
    alias visit_ensure visit_child_nodes

    # Visit an ExcessedComma node.
    alias visit_excessed_comma visit_child_nodes

    # Visit a Field node.
    alias visit_field visit_child_nodes

    # Visit a FloatLiteral node.
    alias visit_float visit_child_nodes

    # Visit a FndPtn node.
    alias visit_fndptn visit_child_nodes

    # Visit a For node.
    alias visit_for visit_child_nodes

    # Visit a GVar node.
    alias visit_gvar visit_child_nodes

    # Visit a HashLiteral node.
    alias visit_hash visit_child_nodes

    # Visit a Heredoc node.
    alias visit_heredoc visit_child_nodes

    # Visit a HeredocBeg node.
    alias visit_heredoc_beg visit_child_nodes

    # Visit a HeredocEnd node.
    alias visit_heredoc_end visit_child_nodes

    # Visit a HshPtn node.
    alias visit_hshptn visit_child_nodes

    # Visit an Ident node.
    alias visit_ident visit_child_nodes

    # Visit an IfNode node.
    alias visit_if visit_child_nodes

    # Visit an IfOp node.
    alias visit_if_op visit_child_nodes

    # Visit an Imaginary node.
    alias visit_imaginary visit_child_nodes

    # Visit an In node.
    alias visit_in visit_child_nodes

    # Visit an Int node.
    alias visit_int visit_child_nodes

    # Visit an IVar node.
    alias visit_ivar visit_child_nodes

    # Visit a Kw node.
    alias visit_kw visit_child_nodes

    # Visit a KwRestParam node.
    alias visit_kwrest_param visit_child_nodes

    # Visit a Label node.
    alias visit_label visit_child_nodes

    # Visit a LabelEnd node.
    alias visit_label_end visit_child_nodes

    # Visit a Lambda node.
    alias visit_lambda visit_child_nodes

    # Visit a LambdaVar node.
    alias visit_lambda_var visit_child_nodes

    # Visit a LBrace node.
    alias visit_lbrace visit_child_nodes

    # Visit a LBracket node.
    alias visit_lbracket visit_child_nodes

    # Visit a LParen node.
    alias visit_lparen visit_child_nodes

    # Visit a MAssign node.
    alias visit_massign visit_child_nodes

    # Visit a MethodAddBlock node.
    alias visit_method_add_block visit_child_nodes

    # Visit a MLHS node.
    alias visit_mlhs visit_child_nodes

    # Visit a MLHSParen node.
    alias visit_mlhs_paren visit_child_nodes

    # Visit a ModuleDeclaration node.
    alias visit_module visit_child_nodes

    # Visit a MRHS node.
    alias visit_mrhs visit_child_nodes

    # Visit a Next node.
    alias visit_next visit_child_nodes

    # Visit a Not node.
    alias visit_not visit_child_nodes

    # Visit an Op node.
    alias visit_op visit_child_nodes

    # Visit an OpAssign node.
    alias visit_opassign visit_child_nodes

    # Visit a Params node.
    alias visit_params visit_child_nodes

    # Visit a Paren node.
    alias visit_paren visit_child_nodes

    # Visit a Period node.
    alias visit_period visit_child_nodes

    # Visit a PinnedBegin node.
    alias visit_pinned_begin visit_child_nodes

    # Visit a PinnedVarRef node.
    alias visit_pinned_var_ref visit_child_nodes

    # Visit a Program node.
    alias visit_program visit_child_nodes

    # Visit a QSymbols node.
    alias visit_qsymbols visit_child_nodes

    # Visit a QSymbolsBeg node.
    alias visit_qsymbols_beg visit_child_nodes

    # Visit a QWords node.
    alias visit_qwords visit_child_nodes

    # Visit a QWordsBeg node.
    alias visit_qwords_beg visit_child_nodes

    # Visit a RangeNode node
    alias visit_range visit_child_nodes

    # Visit a RAssign node.
    alias visit_rassign visit_child_nodes

    # Visit a RationalLiteral node.
    alias visit_rational visit_child_nodes

    # Visit a RBrace node.
    alias visit_rbrace visit_child_nodes

    # Visit a RBracket node.
    alias visit_rbracket visit_child_nodes

    # Visit a Redo node.
    alias visit_redo visit_child_nodes

    # Visit a RegexpBeg node.
    alias visit_regexp_beg visit_child_nodes

    # Visit a RegexpContent node.
    alias visit_regexp_content visit_child_nodes

    # Visit a RegexpEnd node.
    alias visit_regexp_end visit_child_nodes

    # Visit a RegexpLiteral node.
    alias visit_regexp_literal visit_child_nodes

    # Visit a Rescue node.
    alias visit_rescue visit_child_nodes

    # Visit a RescueEx node.
    alias visit_rescue_ex visit_child_nodes

    # Visit a RescueMod node.
    alias visit_rescue_mod visit_child_nodes

    # Visit a RestParam node.
    alias visit_rest_param visit_child_nodes

    # Visit a Retry node.
    alias visit_retry visit_child_nodes

    # Visit a Return node.
    alias visit_return visit_child_nodes

    # Visit a RParen node.
    alias visit_rparen visit_child_nodes

    # Visit a SClass node.
    alias visit_sclass visit_child_nodes

    # Visit a Statements node.
    alias visit_statements visit_child_nodes

    # Visit a StringConcat node.
    alias visit_string_concat visit_child_nodes

    # Visit a StringContent node.
    alias visit_string_content visit_child_nodes

    # Visit a StringDVar node.
    alias visit_string_dvar visit_child_nodes

    # Visit a StringEmbExpr node.
    alias visit_string_embexpr visit_child_nodes

    # Visit a StringLiteral node.
    alias visit_string_literal visit_child_nodes

    # Visit a Super node.
    alias visit_super visit_child_nodes

    # Visit a SymBeg node.
    alias visit_symbeg visit_child_nodes

    # Visit a SymbolContent node.
    alias visit_symbol_content visit_child_nodes

    # Visit a SymbolLiteral node.
    alias visit_symbol_literal visit_child_nodes

    # Visit a Symbols node.
    alias visit_symbols visit_child_nodes

    # Visit a SymbolsBeg node.
    alias visit_symbols_beg visit_child_nodes

    # Visit a TLambda node.
    alias visit_tlambda visit_child_nodes

    # Visit a TLamBeg node.
    alias visit_tlambeg visit_child_nodes

    # Visit a TopConstField node.
    alias visit_top_const_field visit_child_nodes

    # Visit a TopConstRef node.
    alias visit_top_const_ref visit_child_nodes

    # Visit a TStringBeg node.
    alias visit_tstring_beg visit_child_nodes

    # Visit a TStringContent node.
    alias visit_tstring_content visit_child_nodes

    # Visit a TStringEnd node.
    alias visit_tstring_end visit_child_nodes

    # Visit an Unary node.
    alias visit_unary visit_child_nodes

    # Visit an Undef node.
    alias visit_undef visit_child_nodes

    # Visit an UnlessNode node.
    alias visit_unless visit_child_nodes

    # Visit an UntilNode node.
    alias visit_until visit_child_nodes

    # Visit a VarField node.
    alias visit_var_field visit_child_nodes

    # Visit a VarRef node.
    alias visit_var_ref visit_child_nodes

    # Visit a VCall node.
    alias visit_vcall visit_child_nodes

    # Visit a VoidStmt node.
    alias visit_void_stmt visit_child_nodes

    # Visit a When node.
    alias visit_when visit_child_nodes

    # Visit a WhileNode node.
    alias visit_while visit_child_nodes

    # Visit a Word node.
    alias visit_word visit_child_nodes

    # Visit a Words node.
    alias visit_words visit_child_nodes

    # Visit a WordsBeg node.
    alias visit_words_beg visit_child_nodes

    # Visit a XString node.
    alias visit_xstring visit_child_nodes

    # Visit a XStringLiteral node.
    alias visit_xstring_literal visit_child_nodes

    # Visit a YieldNode node.
    alias visit_yield visit_child_nodes

    # Visit a ZSuper node.
    alias visit_zsuper visit_child_nodes

    # Visit an EndContent node.
    alias visit___end__ visit_child_nodes
  end
end
