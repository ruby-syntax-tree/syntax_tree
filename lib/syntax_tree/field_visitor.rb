# frozen_string_literal: true

module SyntaxTree
  # This is the parent class of a lot of built-in visitors for Syntax Tree. It
  # reflects visiting each of the fields on every node in turn. It itself does
  # not do anything with these fields, it leaves that behavior up to the
  # subclass to implement.
  #
  # In order to properly use this class, you will need to subclass it and
  # implement #comments, #field, #list, #node, #pairs, and #text. Those are
  # documented here.
  #
  # == comments(node)
  #
  # This accepts the node that is being visited and does something depending on
  # the comments attached to the node.
  #
  # == field(name, value)
  #
  # This accepts the name of the field being visited as a string (like "value")
  # and the actual value of that field. The value can be a subclass of Node or
  # any other type that can be held within the tree.
  #
  # == list(name, values)
  #
  # This accepts the name of the field being visited as well as a list of
  # values. This is used, for example, when visiting something like the body of
  # a Statements node.
  #
  # == node(name, node)
  #
  # This is the parent serialization method for each node. It is called with the
  # node itself, as well as the type of the node as a string. The type is an
  # internally used value that usually resembles the name of the ripper event
  # that generated the node. The method should yield to the given block which
  # then calls through to visit each of the fields on the node.
  #
  # == text(name, value)
  #
  # This accepts the name of the field being visited as well as a string value
  # representing the value of the field.
  #
  # == pairs(name, values)
  #
  # This accepts the name of the field being visited as well as a list of pairs
  # that represent the value of the field. It is used only in a couple of
  # circumstances, like when visiting the list of optional parameters defined on
  # a method.
  #
  class FieldVisitor < BasicVisitor
    visit_methods do
      def visit_aref(node)
        node(node, "aref") do
          field("collection", node.collection)
          field("index", node.index)
          comments(node)
        end
      end

      def visit_aref_field(node)
        node(node, "aref_field") do
          field("collection", node.collection)
          field("index", node.index)
          comments(node)
        end
      end

      def visit_alias(node)
        node(node, "alias") do
          field("left", node.left)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_arg_block(node)
        node(node, "arg_block") do
          field("value", node.value) if node.value
          comments(node)
        end
      end

      def visit_arg_paren(node)
        node(node, "arg_paren") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_arg_star(node)
        node(node, "arg_star") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_args(node)
        node(node, "args") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_args_forward(node)
        node(node, "args_forward") { comments(node) }
      end

      def visit_array(node)
        node(node, "array") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_aryptn(node)
        node(node, "aryptn") do
          field("constant", node.constant) if node.constant
          list("requireds", node.requireds) if node.requireds.any?
          field("rest", node.rest) if node.rest
          list("posts", node.posts) if node.posts.any?
          comments(node)
        end
      end

      def visit_assign(node)
        node(node, "assign") do
          field("target", node.target)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_assoc(node)
        node(node, "assoc") do
          field("key", node.key)
          field("value", node.value) if node.value
          comments(node)
        end
      end

      def visit_assoc_splat(node)
        node(node, "assoc_splat") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_backref(node)
        visit_token(node, "backref")
      end

      def visit_backtick(node)
        visit_token(node, "backtick")
      end

      def visit_bare_assoc_hash(node)
        node(node, "bare_assoc_hash") do
          list("assocs", node.assocs)
          comments(node)
        end
      end

      def visit_BEGIN(node)
        node(node, "BEGIN") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_begin(node)
        node(node, "begin") do
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_binary(node)
        node(node, "binary") do
          field("left", node.left)
          text("operator", node.operator)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_block(node)
        node(node, "block") do
          field("block_var", node.block_var) if node.block_var
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_blockarg(node)
        node(node, "blockarg") do
          field("name", node.name) if node.name
          comments(node)
        end
      end

      def visit_block_var(node)
        node(node, "block_var") do
          field("params", node.params)
          list("locals", node.locals) if node.locals.any?
          comments(node)
        end
      end

      def visit_bodystmt(node)
        node(node, "bodystmt") do
          field("statements", node.statements)
          field("rescue_clause", node.rescue_clause) if node.rescue_clause
          field("else_clause", node.else_clause) if node.else_clause
          field("ensure_clause", node.ensure_clause) if node.ensure_clause
          comments(node)
        end
      end

      def visit_break(node)
        node(node, "break") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_call(node)
        node(node, "call") do
          field("receiver", node.receiver)
          field("operator", node.operator)
          field("message", node.message)
          field("arguments", node.arguments) if node.arguments
          comments(node)
        end
      end

      def visit_case(node)
        node(node, "case") do
          field("keyword", node.keyword)
          field("value", node.value) if node.value
          field("consequent", node.consequent)
          comments(node)
        end
      end

      def visit_CHAR(node)
        visit_token(node, "CHAR")
      end

      def visit_class(node)
        node(node, "class") do
          field("constant", node.constant)
          field("superclass", node.superclass) if node.superclass
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_comma(node)
        node(node, "comma") { field("value", node.value) }
      end

      def visit_command(node)
        node(node, "command") do
          field("message", node.message)
          field("arguments", node.arguments)
          field("block", node.block) if node.block
          comments(node)
        end
      end

      def visit_command_call(node)
        node(node, "command_call") do
          field("receiver", node.receiver)
          field("operator", node.operator)
          field("message", node.message)
          field("arguments", node.arguments) if node.arguments
          field("block", node.block) if node.block
          comments(node)
        end
      end

      def visit_comment(node)
        node(node, "comment") { field("value", node.value) }
      end

      def visit_const(node)
        visit_token(node, "const")
      end

      def visit_const_path_field(node)
        node(node, "const_path_field") do
          field("parent", node.parent)
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_const_path_ref(node)
        node(node, "const_path_ref") do
          field("parent", node.parent)
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_const_ref(node)
        node(node, "const_ref") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_cvar(node)
        visit_token(node, "cvar")
      end

      def visit_def(node)
        node(node, "def") do
          field("target", node.target)
          field("operator", node.operator)
          field("name", node.name)
          field("params", node.params)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_defined(node)
        node(node, "defined") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_dyna_symbol(node)
        node(node, "dyna_symbol") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_END(node)
        node(node, "END") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_else(node)
        node(node, "else") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_elsif(node)
        node(node, "elsif") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_embdoc(node)
        node(node, "embdoc") { field("value", node.value) }
      end

      def visit_embexpr_beg(node)
        node(node, "embexpr_beg") { field("value", node.value) }
      end

      def visit_embexpr_end(node)
        node(node, "embexpr_end") { field("value", node.value) }
      end

      def visit_embvar(node)
        node(node, "embvar") { field("value", node.value) }
      end

      def visit_ensure(node)
        node(node, "ensure") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_excessed_comma(node)
        visit_token(node, "excessed_comma")
      end

      def visit_field(node)
        node(node, "field") do
          field("parent", node.parent)
          field("operator", node.operator)
          field("name", node.name)
          comments(node)
        end
      end

      def visit_float(node)
        visit_token(node, "float")
      end

      def visit_fndptn(node)
        node(node, "fndptn") do
          field("constant", node.constant) if node.constant
          field("left", node.left)
          list("values", node.values)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_for(node)
        node(node, "for") do
          field("index", node.index)
          field("collection", node.collection)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_gvar(node)
        visit_token(node, "gvar")
      end

      def visit_hash(node)
        node(node, "hash") do
          list("assocs", node.assocs) if node.assocs.any?
          comments(node)
        end
      end

      def visit_heredoc(node)
        node(node, "heredoc") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_heredoc_beg(node)
        visit_token(node, "heredoc_beg")
      end

      def visit_heredoc_end(node)
        visit_token(node, "heredoc_end")
      end

      def visit_hshptn(node)
        node(node, "hshptn") do
          field("constant", node.constant) if node.constant
          pairs("keywords", node.keywords) if node.keywords.any?
          field("keyword_rest", node.keyword_rest) if node.keyword_rest
          comments(node)
        end
      end

      def visit_ident(node)
        visit_token(node, "ident")
      end

      def visit_if(node)
        node(node, "if") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_if_op(node)
        node(node, "if_op") do
          field("predicate", node.predicate)
          field("truthy", node.truthy)
          field("falsy", node.falsy)
          comments(node)
        end
      end

      def visit_imaginary(node)
        visit_token(node, "imaginary")
      end

      def visit_in(node)
        node(node, "in") do
          field("pattern", node.pattern)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_int(node)
        visit_token(node, "int")
      end

      def visit_ivar(node)
        visit_token(node, "ivar")
      end

      def visit_kw(node)
        visit_token(node, "kw")
      end

      def visit_kwrest_param(node)
        node(node, "kwrest_param") do
          field("name", node.name)
          comments(node)
        end
      end

      def visit_label(node)
        visit_token(node, "label")
      end

      def visit_label_end(node)
        node(node, "label_end") { field("value", node.value) }
      end

      def visit_lambda(node)
        node(node, "lambda") do
          field("params", node.params)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_lambda_var(node)
        node(node, "lambda_var") do
          field("params", node.params)
          list("locals", node.locals) if node.locals.any?
          comments(node)
        end
      end

      def visit_lbrace(node)
        visit_token(node, "lbrace")
      end

      def visit_lbracket(node)
        visit_token(node, "lbracket")
      end

      def visit_lparen(node)
        visit_token(node, "lparen")
      end

      def visit_massign(node)
        node(node, "massign") do
          field("target", node.target)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_method_add_block(node)
        node(node, "method_add_block") do
          field("call", node.call)
          field("block", node.block)
          comments(node)
        end
      end

      def visit_mlhs(node)
        node(node, "mlhs") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_mlhs_paren(node)
        node(node, "mlhs_paren") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_module(node)
        node(node, "module") do
          field("constant", node.constant)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_mrhs(node)
        node(node, "mrhs") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_next(node)
        node(node, "next") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_not(node)
        node(node, "not") do
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_op(node)
        visit_token(node, "op")
      end

      def visit_opassign(node)
        node(node, "opassign") do
          field("target", node.target)
          field("operator", node.operator)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_params(node)
        node(node, "params") do
          list("requireds", node.requireds) if node.requireds.any?
          pairs("optionals", node.optionals) if node.optionals.any?
          field("rest", node.rest) if node.rest
          list("posts", node.posts) if node.posts.any?
          pairs("keywords", node.keywords) if node.keywords.any?
          field("keyword_rest", node.keyword_rest) if node.keyword_rest
          field("block", node.block) if node.block
          comments(node)
        end
      end

      def visit_paren(node)
        node(node, "paren") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_period(node)
        visit_token(node, "period")
      end

      def visit_pinned_begin(node)
        node(node, "pinned_begin") do
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_pinned_var_ref(node)
        node(node, "pinned_var_ref") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_program(node)
        node(node, "program") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_qsymbols(node)
        node(node, "qsymbols") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_qsymbols_beg(node)
        node(node, "qsymbols_beg") { field("value", node.value) }
      end

      def visit_qwords(node)
        node(node, "qwords") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_qwords_beg(node)
        node(node, "qwords_beg") { field("value", node.value) }
      end

      def visit_range(node)
        node(node, "range") do
          field("left", node.left) if node.left
          field("operator", node.operator)
          field("right", node.right) if node.right
          comments(node)
        end
      end

      def visit_rassign(node)
        node(node, "rassign") do
          field("value", node.value)
          field("operator", node.operator)
          field("pattern", node.pattern)
          comments(node)
        end
      end

      def visit_rational(node)
        visit_token(node, "rational")
      end

      def visit_rbrace(node)
        node(node, "rbrace") { field("value", node.value) }
      end

      def visit_rbracket(node)
        node(node, "rbracket") { field("value", node.value) }
      end

      def visit_redo(node)
        node(node, "redo") { comments(node) }
      end

      def visit_regexp_beg(node)
        node(node, "regexp_beg") { field("value", node.value) }
      end

      def visit_regexp_content(node)
        node(node, "regexp_content") { list("parts", node.parts) }
      end

      def visit_regexp_end(node)
        node(node, "regexp_end") { field("value", node.value) }
      end

      def visit_regexp_literal(node)
        node(node, "regexp_literal") do
          list("parts", node.parts)
          field("options", node.options)
          comments(node)
        end
      end

      def visit_rescue(node)
        node(node, "rescue") do
          field("exception", node.exception) if node.exception
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_rescue_ex(node)
        node(node, "rescue_ex") do
          field("exceptions", node.exceptions)
          field("variable", node.variable)
          comments(node)
        end
      end

      def visit_rescue_mod(node)
        node(node, "rescue_mod") do
          field("statement", node.statement)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_rest_param(node)
        node(node, "rest_param") do
          field("name", node.name)
          comments(node)
        end
      end

      def visit_retry(node)
        node(node, "retry") { comments(node) }
      end

      def visit_return(node)
        node(node, "return") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_rparen(node)
        node(node, "rparen") { field("value", node.value) }
      end

      def visit_sclass(node)
        node(node, "sclass") do
          field("target", node.target)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_statements(node)
        node(node, "statements") do
          list("body", node.body)
          comments(node)
        end
      end

      def visit_string_concat(node)
        node(node, "string_concat") do
          field("left", node.left)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_string_content(node)
        node(node, "string_content") { list("parts", node.parts) }
      end

      def visit_string_dvar(node)
        node(node, "string_dvar") do
          field("variable", node.variable)
          comments(node)
        end
      end

      def visit_string_embexpr(node)
        node(node, "string_embexpr") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_string_literal(node)
        node(node, "string_literal") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_super(node)
        node(node, "super") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_symbeg(node)
        node(node, "symbeg") { field("value", node.value) }
      end

      def visit_symbol_content(node)
        node(node, "symbol_content") { field("value", node.value) }
      end

      def visit_symbol_literal(node)
        node(node, "symbol_literal") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_symbols(node)
        node(node, "symbols") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_symbols_beg(node)
        node(node, "symbols_beg") { field("value", node.value) }
      end

      def visit_tlambda(node)
        node(node, "tlambda") { field("value", node.value) }
      end

      def visit_tlambeg(node)
        node(node, "tlambeg") { field("value", node.value) }
      end

      def visit_top_const_field(node)
        node(node, "top_const_field") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_top_const_ref(node)
        node(node, "top_const_ref") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_tstring_beg(node)
        node(node, "tstring_beg") { field("value", node.value) }
      end

      def visit_tstring_content(node)
        visit_token(node, "tstring_content")
      end

      def visit_tstring_end(node)
        node(node, "tstring_end") { field("value", node.value) }
      end

      def visit_unary(node)
        node(node, "unary") do
          field("operator", node.operator)
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_undef(node)
        node(node, "undef") do
          list("symbols", node.symbols)
          comments(node)
        end
      end

      def visit_unless(node)
        node(node, "unless") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_until(node)
        node(node, "until") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_var_field(node)
        node(node, "var_field") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_var_ref(node)
        node(node, "var_ref") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_vcall(node)
        node(node, "vcall") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_void_stmt(node)
        node(node, "void_stmt") { comments(node) }
      end

      def visit_when(node)
        node(node, "when") do
          field("arguments", node.arguments)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_while(node)
        node(node, "while") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_word(node)
        node(node, "word") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_words(node)
        node(node, "words") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_words_beg(node)
        node(node, "words_beg") { field("value", node.value) }
      end

      def visit_xstring(node)
        node(node, "xstring") { list("parts", node.parts) }
      end

      def visit_xstring_literal(node)
        node(node, "xstring_literal") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_yield(node)
        node(node, "yield") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_zsuper(node)
        node(node, "zsuper") { comments(node) }
      end

      def visit___end__(node)
        visit_token(node, "__end__")
      end
    end

    private

    def visit_token(node, type)
      node(node, type) do
        field("value", node.value)
        comments(node)
      end
    end
  end
end
