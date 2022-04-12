  # frozen_string_literal: true

module SyntaxTree
  class Visitor
    class PrettyPrintVisitor < Visitor
      attr_reader :q

      def initialize(q)
        @q = q
      end

      def visit_aref(node)
        node("aref") do
          field("collection", node.collection)
          field("index", node.index)
          comments(node)
        end
      end

      def visit_aref_field(node)
        node("aref_field") do
          field("collection", node.collection)
          field("index", node.index)
          comments(node)
        end
      end

      def visit_alias(node)
        node("alias") do
          field("left", node.left)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_arg_block(node)
        node("arg_block") do
          field("value", node.value) if node.value
          comments(node)
        end
      end

      def visit_arg_paren(node)
        node("arg_paren") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_arg_star(node)
        node("arg_star") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_args(node)
        node("args") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_args_forward(node)
        visit_token("args_forward", node)
      end

      def visit_array(node)
        node("array") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_aryptn(node)
        node("aryptn") do
          field("constant", node.constant) if node.constant
          list("requireds", node.requireds) if node.requireds.any?
          field("rest", node.rest) if node.rest
          list("posts", node.posts) if node.posts.any?
          comments(node)
        end
      end

      def visit_assign(node)
        node("assign") do
          field("target", node.target)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_assoc(node)
        node("assoc") do
          field("key", node.key)
          field("value", node.value) if node.value
          comments(node)
        end
      end

      def visit_assoc_splat(node)
        node("assoc_splat") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_backref(node)
        visit_token("backref", node)
      end

      def visit_backtick(node)
        visit_token("backtick", node)
      end

      def visit_bare_assoc_hash(node)
        node("bare_assoc_hash") do
          list("assocs", node.assocs)
          comments(node)
        end
      end

      def visit_BEGIN(node)
        node("BEGIN") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_begin(node)
        node("begin") do
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_binary(node)
        node("binary") do
          field("left", node.left)
          text("operator", node.operator)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_blockarg(node)
        node("blockarg") do
          field("name", node.name) if node.name
          comments(node)
        end
      end

      def visit_block_var(node)
        node("block_var") do
          field("params", node.params)
          list("locals", node.locals) if node.locals.any?
          comments(node)
        end
      end

      def visit_bodystmt(node)
        node("bodystmt") do
          field("statements", node.statements)
          field("rescue_clause", node.rescue_clause) if node.rescue_clause
          field("else_clause", node.else_clause) if node.else_clause
          field("ensure_clause", node.ensure_clause) if node.ensure_clause
          comments(node)
        end
      end

      def visit_brace_block(node)
        node("brace_block") do
          field("block_var", node.block_var) if node.block_var
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_break(node)
        node("break") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_call(node)
        node("call") do
          field("receiver", node.receiver)
          field("operator", node.operator)
          field("message", node.message)
          field("arguments", node.arguments) if node.arguments
          comments(node)
        end
      end

      def visit_case(node)
        node("case") do
          field("keyword", node.keyword)
          field("value", node.value) if node.value
          field("consequent", node.consequent)
          comments(node)
        end
      end

      def visit_CHAR(node)
        visit_token("CHAR", node)
      end

      def visit_class(node)
        node("class") do
          field("constant", node.constant)
          field("superclass", node.superclass) if node.superclass
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_comma(node)
        node("comma") do
          field("value", node)
        end
      end

      def visit_command(node)
        node("command") do
          field("message", node.message)
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_command_call(node)
        node("command_call") do
          field("receiver", node.receiver)
          field("operator", node.operator)
          field("message", node.message)
          field("arguments", node.arguments) if node.arguments
          comments(node)
        end
      end

      def visit_comment(node)
        node("comment") do
          field("value", node.value)
        end
      end

      def visit_const(node)
        visit_token("const", node)
      end

      def visit_const_path_field(node)
        node("const_path_field") do
          field("parent", node.parent)
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_const_path_ref(node)
        node("const_path_ref") do
          field("parent", node.parent)
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_const_ref(node)
        node("const_ref") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_cvar(node)
        visit_token("cvar", node)
      end

      def visit_def(node)
        node("def") do
          field("name", node.name)
          field("params", node.params)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_def_endless(node)
        node("def_endless") do
          if node.target
            field("target", node.target)
            field("operator", node.operator)
          end

          field("name", node.name)
          field("paren", node.paren) if node.paren
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_defined(node)
        node("defined") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_defs(node)
        node("defs") do
          field("target", node.target)
          field("operator", node.operator)
          field("name", node.name)
          field("params", node.params)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_do_block(node)
        node("do_block") do
          field("block_var", node.block_var) if node.block_var
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_dot2(node)
        node("dot2") do
          field("left", node.left) if node.left
          field("right", node.right) if node.right
          comments(node)
        end
      end

      def visit_dot3(node)
        node("dot3") do
          field("left", node.left) if node.left
          field("right", node.right) if node.right
          comments(node)
        end
      end

      def visit_dyna_symbol(node)
        node("dyna_symbol") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_END(node)
        node("END") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_else(node)
        node("else") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_elsif(node)
        node("elsif") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_embdoc(node)
        node("embdoc") do
          field("value", node.value)
        end
      end

      def visit_embexpr_beg(node)
        node("embexpr_beg") do
          field("value", node.value)
        end
      end

      def visit_embexpr_end(node)
        node("embexpr_end") do
          field("value", node.value)
        end
      end

      def visit_embvar(node)
        node("embvar") do
          field("value", node.value)
        end
      end

      def visit_ensure(node)
        node("ensure") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_excessed_comma(node)
        visit_token("excessed_comma", node)
      end

      def visit_fcall(node)
        node("fcall") do
          field("value", node.value)
          field("arguments", node.arguments) if node.arguments
          comments(node)
        end
      end

      def visit_field(node)
        node("field") do
          field("parent", node.parent)
          field("operator", node.operator)
          field("name", node.name)
          comments(node)
        end
      end

      def visit_float(node)
        visit_token("float", node)
      end

      def visit_fndptn(node)
        node("fndptn") do
          field("constant", node.constant) if node.constant
          field("left", node.left)
          list("values", node.values)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_for(node)
        node("for") do
          field("index", node.index)
          field("collection", node.collection)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_gvar(node)
        visit_token("gvar", node)
      end

      def visit_hash(node)
        node("hash") do
          list("assocs", node.assocs) if node.assocs.any?
          comments(node)
        end
      end

      def visit_heredoc(node)
        node("heredoc") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_heredoc_beg(node)
        visit_token("heredoc_beg", node)
      end

      def visit_hshptn(node)
        node("hshptn") do
          field("constant", node.constant) if node.constant

          if node.keywords.any?
            q.breakable
            q.group(2, "(", ")") do
              q.seplist(node.keywords) do |(key, value)|
                q.group(2, "(", ")") do
                  key.pretty_print(q)

                  if value
                    q.breakable
                    value.pretty_print(q)
                  end
                end
              end
            end
          end

          field("keyword_rest", node.keyword_rest) if node.keyword_rest
          comments(node)
        end
      end

      def visit_ident(node)
        visit_token("ident", node)
      end

      def visit_if(node)
        node("if") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_if_mod(node)
        node("if_mod") do
          field("statement", node.statement)
          field("predicate", node.predicate)
          comments(node)
        end
      end

      def visit_if_op(node)
        node("ifop") do
          field("predicate", node.predicate)
          field("truthy", node.truthy)
          field("falsy", node.falsy)
          comments(node)
        end
      end

      def visit_imaginary(node)
        visit_token("imaginary", node)
      end

      def visit_in(node)
        node("in") do
          field("pattern", node.pattern)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_int(node)
        visit_token("int", node)
      end

      def visit_ivar(node)
        visit_token("ivar", node)
      end

      def visit_kw(node)
        visit_token("kw", node)
      end

      def visit_kwrest_param(node)
        node("kwrest_param") do
          field("name", node.name)
          comments(node)
        end
      end

      def visit_label(node)
        node("label") do
          q.breakable
          q.text(":")
          q.text(node.value[0...-1])
          comments(node)
        end
      end

      def visit_label_end(node)
        node("label_end") do
          field("value", node.value)
        end
      end

      def visit_lambda(node)
        node("lambda") do
          field("params", node.params)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_lbrace(node)
        visit_token("lbrace", node)
      end

      def visit_lbracket(node)
        visit_token("lbracket", node)
      end

      def visit_lparen(node)
        visit_token("lparen", node)
      end

      def visit_massign(node)
        node("massign") do
          field("target", node.target)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_method_add_block(node)
        node("method_add_block") do
          field("call", node.call)
          field("block", node.block)
          comments(node)
        end
      end

      def visit_mlhs(node)
        node("mlhs") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_mlhs_paren(node)
        node("mlhs_paren") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_module(node)
        node("module") do
          field("constant", node.constant)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_mrhs(node)
        node("mrhs") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_next(node)
        node("next") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_not(node)
        node("not") do
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_op(node)
        visit_token("op", node)
      end

      def visit_opassign(node)
        node("opassign") do
          field("target", node.target)
          field("operator", node.operator)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_params(node)
        node("params") do
          list("requireds", node.requireds) if node.requireds.any?

          if node.optionals.any?
            q.breakable
            q.group(2, "(", ")") do
              q.seplist(node.optionals) do |(name, default)|
                name.pretty_print(q)
                q.text("=")
                q.group(2) do
                  q.breakable("")
                  default.pretty_print(q)
                end
              end
            end
          end

          field("rest", node.rest) if node.rest
          list("posts", node.posts) if node.posts.any?
    
          if node.keywords.any?
            q.breakable
            q.group(2, "(", ")") do
              q.seplist(node.keywords) do |(name, default)|
                name.pretty_print(q)

                if default
                  q.text("=")
                  q.group(2) do
                    q.breakable("")
                    default.pretty_print(q)
                  end
                end
              end
            end
          end

          field("keyword_rest", node.keyword_rest) if node.keyword_rest
          field("block", node.block) if node.block
          comments(node)
        end
      end

      def visit_paren(node)
        node("paren") do
          field("contents", node.contents)
          comments(node)
        end
      end

      def visit_period(node)
        visit_token("period", node)
      end

      def visit_pinned_begin(node)
        node("pinned_begin") do
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_pinned_var_ref(node)
        node("pinned_var_ref") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_program(node)
        node("program") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_qsymbols(node)
        node("qsymbols") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_qsymbols_beg(node)
        node("qsymbols_beg") do
          field("value", node.value)
        end
      end

      def visit_qwords(node)
        node("qwords") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_qwords_beg(node)
        node("qwords_beg") do
          field("value", node.value)
        end
      end

      def visit_rassign(node)
        node("rassign") do
          field("value", node.value)
          field("operator", node.operator)
          field("pattern", node.pattern)
          comments(node)
        end
      end

      def visit_rational(node)
        visit_token("rational", node)
      end

      def visit_rbrace(node)
        node("rbrace") do
          field("value", node.value)
        end
      end

      def visit_rbracket(node)
        node("rbracket") do
          field("value", node.value)
        end
      end

      def visit_redo(node)
        visit_token("redo", node)
      end

      def visit_regexp_beg(node)
        node("regexp_beg") do
          field("value", node.value)
        end
      end

      def visit_regexp_content(node)
        node("regexp_content") do
          list("parts", node.parts)
        end
      end

      def visit_regexp_end(node)
        node("regexp_end") do
          field("value", node.value)
        end
      end

      def visit_regexp_literal(node)
        node("regexp_literal") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_rescue(node)
        node("rescue") do
          field("exception", node.exception) if node.exception
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_rescue_ex(node)
        node("rescue_ex") do
          field("exceptions", node.exceptions)
          field("variable", node.variable)
          comments(node)
        end
      end

      def visit_rescue_mod(node)
        node("rescue_mod") do
          field("statement", node.statement)
          field("value", node.value)
          comments(node)
        end
      end

      def visit_rest_param(node)
        node("rest_param") do
          field("name", node.name)
          comments(node)
        end
      end

      def visit_retry(node)
        visit_token("retry", node)
      end

      def visit_return(node)
        node("return") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_return0(node)
        visit_token("return0", node)
      end

      def visit_rparen(node)
        node("rparen") do
          field("value", node.value)
        end
      end

      def visit_sclass(node)
        node("sclass") do
          field("target", node.target)
          field("bodystmt", node.bodystmt)
          comments(node)
        end
      end

      def visit_statements(node)
        node("statements") do
          list("body", node.body)
          comments(node)
        end
      end

      def visit_string_concat(node)
        node("string_concat") do
          field("left", node.left)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_string_content(node)
        node("string_content") do
          list("parts", node.parts)
        end
      end

      def visit_string_dvar(node)
        node("string_dvar") do
          field("variable", node.variable)
          comments(node)
        end
      end

      def visit_string_embexpr(node)
        node("string_embexpr") do
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_string_literal(node)
        node("string_literal") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_super(node)
        node("super") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_symbeg(node)
        node("symbeg") do
          field("value", node.value)
        end
      end

      def visit_symbol_content(node)
        node("symbol_content") do
          field("value", node.value)
        end
      end

      def visit_symbol_literal(node)
        node("symbol_literal") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_symbols(node)
        node("symbols") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_symbols_beg(node)
        node("symbols_beg") do
          field("value", node.value)
        end
      end

      def visit_tlambda(node)
        node("tlambda") do
          field("value", node.value)
        end
      end

      def visit_tlambeg(node)
        node("tlambeg") do
          field("value", node.value)
        end
      end

      def visit_top_const_field(node)
        node("top_const_field") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_top_const_ref(node)
        node("top_const_ref") do
          field("constant", node.constant)
          comments(node)
        end
      end

      def visit_tstring_beg(node)
        node("tstring_beg") do
          field("value", node.value)
        end
      end

      def visit_tstring_content(node)
        visit_token("tstring_content", node)
      end

      def visit_tstring_end(node)
        node("tstring_end") do
          field("value", node.value)
        end
      end

      def visit_unary(node)
        node("unary") do
          field("operator", node.operator)
          field("statement", node.statement)
          comments(node)
        end
      end

      def visit_undef(node)
        node("undef") do
          list("symbols", node.symbols)
          comments(node)
        end
      end

      def visit_unless(node)
        node("unless") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_unless_mod(node)
        node("unless_mod") do
          field("statement", node.statement)
          field("predicate", node.predicate)
          comments(node)
        end
      end

      def visit_until(node)
        node("until") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_until_mod(node)
        node("until_mod") do
          field("statement", node.statement)
          field("predicate", node.predicate)
          comments(node)
        end
      end

      def visit_var_alias(node)
        node("var_alias") do
          field("left", node.left)
          field("right", node.right)
          comments(node)
        end
      end

      def visit_var_field(node)
        node("var_field") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_var_ref(node)
        node("var_ref") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_vcall(node)
        node("vcall") do
          field("value", node.value)
          comments(node)
        end
      end

      def visit_void_stmt(node)
        node("void_stmt") do
          comments(node)
        end
      end

      def visit_when(node)
        node("when") do
          field("arguments", node.arguments)
          field("statements", node.statements)
          field("consequent", node.consequent) if node.consequent
          comments(node)
        end
      end

      def visit_while(node)
        node("while") do
          field("predicate", node.predicate)
          field("statements", node.statements)
          comments(node)
        end
      end

      def visit_while_mod(node)
        node("while_mod") do
          field("statement", node.statement)
          field("predicate", node.predicate)
          comments(node)
        end
      end

      def visit_word(node)
        node("word") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_words(node)
        node("words") do
          list("elements", node.elements)
          comments(node)
        end
      end

      def visit_words_beg(node)
        node("words_beg") do
          field("value", node.value)
        end
      end

      def visit_xstring(node)
        node("xstring") do
          list("parts", node.parts)
        end
      end

      def visit_xstring_literal(node)
        node("xstring_literal") do
          list("parts", node.parts)
          comments(node)
        end
      end

      def visit_yield(node)
        node("yield") do
          field("arguments", node.arguments)
          comments(node)
        end
      end

      def visit_yield0(node)
        visit_token("yield0", node)
      end

      def visit_zsuper(node)
        visit_token("zsuper", node)
      end

      def visit___end__(node)
        visit_token("__end__", node)
      end

      private

      def comments(node)
        return if node.comments.empty?

        q.breakable
        q.group(2, "(", ")") do
          q.seplist(node.comments) { |comment| comment.pretty_print(q) }
        end
      end

      def field(_name, value)
        q.breakable

        # I don't entirely know why this is necessary, but in Ruby 2.7 there is
        # an issue with calling q.pp on strings that somehow involves inspect
        # keys. I'm purposefully avoiding the inspect key stuff here because I
        # know the tree does not contain any cycles.
        value.is_a?(String) ? q.text(value.inspect) : value.pretty_print(q)
      end

      def list(_name, values)
        q.breakable
        q.group(2, "(", ")") do
          q.seplist(values) { |value| value.pretty_print(q) }
        end
      end

      def node(type)
        q.group(2, "(", ")") do
          q.text(type)
          yield
        end
      end

      def text(_name, value)
        q.breakable
        q.text(value)
      end

      def visit_token(type, node)
        node(type) do
          field("value", node.value)
          comments(node)
        end
      end
    end
  end
end
