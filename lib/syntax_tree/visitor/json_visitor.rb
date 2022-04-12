  # frozen_string_literal: true

module SyntaxTree
  class Visitor
    class JSONVisitor < Visitor
      def visit_aref(node)
        {
          type: :aref,
          collection: visit(node.collection),
          index: visit(node.index),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_aref_field(node)
        {
          type: :aref_field,
          collection: visit(node.collection),
          index: visit(node.index),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_alias(node)
        {
          type: :alias,
          left: visit(node.left),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_arg_block(node)
        {
          type: :arg_block,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_arg_paren(node)
        {
          type: :arg_paren,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_arg_star(node)
        {
          type: :arg_star,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_args(node)
        {
          type: :args,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_args_forward(node)
        visit_token(:args_forward, node)
      end

      def visit_array(node)
        {
          type: :array,
          cnts: visit(node.contents),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_aryptn(node)
        {
          type: :aryptn,
          constant: visit(node.constant),
          reqs: visit_all(node.requireds),
          rest: visit(node.rest),
          posts: visit_all(node.posts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_assign(node)
        {
          type: :assign,
          target: visit(node.target),
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_assoc(node)
        {
          type: :assoc,
          key: visit(node.key),
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_assoc_splat(node)
        {
          type: :assoc_splat,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_backref(node)
        visit_token(:backref, node)
      end

      def visit_backtick(node)
        visit_token(:backtick, node)
      end

      def visit_bare_assoc_hash(node)
        {
          type: :bare_assoc_hash,
          assocs: visit_all(node.assocs),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_BEGIN(node)
        {
          type: :BEGIN,
          lbrace: visit(node.lbrace),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_begin(node)
        {
          type: :begin,
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_binary(node)
        {
          type: :binary,
          left: visit(node.left),
          op: node.operator,
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_blockarg(node)
        {
          type: :blockarg,
          name: visit(node.name),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_block_var(node)
        {
          type: :block_var,
          params: visit(node.params),
          locals: visit_all(node.locals),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_bodystmt(node)
        {
          type: :bodystmt,
          stmts: visit(node.statements),
          rsc: visit(node.rescue_clause),
          els: visit(node.else_clause),
          ens: visit(node.ensure_clause),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_brace_block(node)
        {
          type: :brace_block,
          lbrace: visit(node.lbrace),
          block_var: visit(node.block_var),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_break(node)
        {
          type: :break,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_call(node)
        {
          type: :call,
          receiver: visit(node.receiver),
          op: visit_call_operator(node.operator),
          message: node.message == :call ? :call : visit(node.message),
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_case(node)
        {
          type: :case,
          value: visit(node.value),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_CHAR(node)
        visit_token(:CHAR, node)
      end

      def visit_class(node)
        {
          type: :class,
          constant: visit(node.constant),
          superclass: visit(node.superclass),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_comma(node)
        visit_token(:comma, node)
      end

      def visit_command(node)
        {
          type: :command,
          message: visit(node.message),
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_command_call(node)
        {
          type: :command_call,
          receiver: visit(node.receiver),
          op: visit_call_operator(node.operator),
          message: visit(node.message),
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_comment(node)
        {
          type: :comment,
          value: node.value,
          inline: node.inline,
          loc: visit_location(node.location)
        }
      end

      def visit_const(node)
        visit_token(:const, node)
      end

      def visit_const_path_field(node)
        {
          type: :const_path_field,
          parent: visit(node.parent),
          constant: visit(node.constant),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_const_path_ref(node)
        {
          type: :const_path_ref,
          parent: visit(node.parent),
          constant: visit(node.constant),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_const_ref(node)
        {
          type: :const_ref,
          constant: visit(node.constant),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_cvar(node)
        visit_token(:cvar, node)
      end

      def visit_def(node)
        {
          type: :def,
          name: visit(node.name),
          params: visit(node.params),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_def_endless(node)
        {
          type: :def_endless,
          name: visit(node.name),
          paren: visit(node.paren),
          stmt: visit(node.statement),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_defined(node)
        visit_token(:defined, node)
      end

      def visit_defs(node)
        {
          type: :defs,
          target: visit(node.target),
          op: visit(node.operator),
          name: visit(node.name),
          params: visit(node.params),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_do_block(node)
        {
          type: :do_block,
          keyword: visit(node.keyword),
          block_var: visit(node.block_var),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_dot2(node)
        {
          type: :dot2,
          left: visit(node.left),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_dot3(node)
        {
          type: :dot3,
          left: visit(node.left),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_dyna_symbol(node)
        {
          type: :dyna_symbol,
          parts: visit_all(node.parts),
          quote: node.quote,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_END(node)
        {
          type: :END,
          lbrace: visit(node.lbrace),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_else(node)
        {
          type: :else,
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_elsif(node)
        {
          type: :elsif,
          pred: visit(node.predicate),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_embdoc(node)
        {
          type: :embdoc,
          value: node.value,
          loc: visit_location(node.location)
        }
      end

      def visit_embexpr_beg(node)
        {
          type: :embexpr_beg,
          value: node.value,
          loc: visit_location(node.location)
        }
      end

      def visit_embexpr_end(node)
        {
          type: :embexpr_end,
          value: node.value,
          loc: visit_location(node.location)
        }
      end

      def visit_embvar(node)
        {
          type: :embvar,
          value: node.value,
          loc: visit_location(node.location)
        }
      end

      def visit_ensure(node)
        {
          type: :ensure,
          keyword: visit(node.keyword),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_excessed_comma(node)
        visit_token(:excessed_comma, node)
      end

      def visit_fcall(node)
        {
          type: :fcall,
          value: visit(node.value),
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_field(node)
        {
          type: :field,
          parent: visit(node.parent),
          op: visit_call_operator(node.operator),
          name: visit(node.name),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_float(node)
        visit_token(:float, node)
      end

      def visit_fndptn(node)
        {
          type: :fndptn,
          constant: visit(node.constant),
          left: visit(node.left),
          values: visit_all(node.values),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_for(node)
        {
          type: :for,
          index: visit(node.index),
          collection: visit(node.collection),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_gvar(node)
        visit_token(:gvar, node)
      end

      def visit_hash(node)
        {
          type: :hash,
          assocs: visit_all(node.assocs),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_heredoc(node)
        {
          type: :heredoc,
          beging: visit(node.beginning),
          ending: node.ending,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_heredoc_beg(node)
        visit_token(:heredoc_beg, node)
      end

      def visit_hshptn(node)
        {
          type: :hshptn,
          constant: visit(node.constant),
          keywords: node.keywords.map { |(name, value)| [visit(name), visit(value)] },
          kwrest: visit(node.keyword_rest),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_ident(node)
        visit_token(:ident, node)
      end

      def visit_if(node)
        {
          type: :if,
          pred: visit(node.predicate),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_if_mod(node)
        {
          type: :if_mod,
          stmt: visit(node.statement),
          pred: visit(node.predicate),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_if_op(node)
        {
          type: :ifop,
          pred: visit(node.predicate),
          tthy: visit(node.truthy),
          flsy: visit(node.falsy),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_imaginary(node)
        visit_token(:imaginary, node)
      end

      def visit_in(node)
        {
          type: :in,
          pattern: visit(node.pattern),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_int(node)
        visit_token(:int, node)
      end

      def visit_ivar(node)
        visit_token(:ivar, node)
      end

      def visit_kw(node)
        visit_token(:kw, node)
      end

      def visit_kwrest_param(node)
        {
          type: :kwrest_param,
          name: visit(node.name),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_label(node)
        visit_token(:label, node)
      end

      def visit_label_end(node)
        visit_token(:label_end, node)
      end

      def visit_lambda(node)
        {
          type: :lambda,
          params: visit(node.params),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_lbrace(node)
        visit_token(:lbrace, node)
      end

      def visit_lbracket(node)
        visit_token(:lbracket, node)
      end

      def visit_lparen(node)
        visit_token(:lparen, node)
      end

      def visit_massign(node)
        {
          type: :massign,
          target: visit(node.target),
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_method_add_block(node)
        {
          type: :method_add_block,
          call: visit(node.call),
          block: visit(node.block),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_mlhs(node)
        {
          type: :mlhs,
          parts: visit_all(node.parts),
          comma: node.comma,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_mlhs_paren(node)
        {
          type: :mlhs_paren,
          cnts: visit(node.contents),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_module(node)
        {
          type: :module,
          constant: visit(node.constant),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_mrhs(node)
        {
          type: :mrhs,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_next(node)
        {
          type: :next,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_not(node)
        {
          type: :not,
          value: visit(node.statement),
          paren: node.parentheses,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_op(node)
        visit_token(:op, node)
      end

      def visit_opassign(node)
        {
          type: :opassign,
          target: visit(node.target),
          op: visit(node.operator),
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_params(node)
        {
          type: :params,
          reqs: visit_all(node.requireds),
          opts: node.optionals.map { |(name, value)| [visit(name), visit(value)] },
          rest: visit(node.rest),
          posts: visit_all(node.posts),
          keywords: node.keywords.map { |(name, value)| [visit(name), visit(value || nil)] },
          kwrest: node.keyword_rest == :nil ? "nil" : visit(node.keyword_rest),
          block: visit(node.block),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_paren(node)
        {
          type: :paren,
          lparen: visit(node.lparen),
          cnts: visit(node.contents),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_period(node)
        visit_token(:period, node)
      end

      def visit_pinned_begin(node)
        {
          type: :pinned_begin,
          stmt: visit(node.statement),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_pinned_var_ref(node)
        {
          type: :pinned_var_ref,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_program(node)
        {
          type: :program,
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_qsymbols(node)
        {
          type: :qsymbols,
          elems: visit_all(node.elements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_qsymbols_beg(node)
        visit_token(:qsymbols_beg, node)
      end

      def visit_qwords(node)
        {
          type: :qwords,
          elems: visit_all(node.elements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_qwords_beg(node)
        visit_token(:qwords_beg, node)
      end

      def visit_rassign(node)
        {
          type: :rassign,
          value: visit(node.value),
          op: visit(node.operator),
          pattern: visit(node.pattern),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_rational(node)
        visit_token(:rational, node)
      end

      def visit_rbrace(node)
        visit_token(:rbrace, node)
      end

      def visit_rbracket(node)
        visit_token(:rbracket, node)
      end

      def visit_redo(node)
        visit_token(:redo, node)
      end

      def visit_regexp_beg(node)
        visit_token(:regexp_beg, node)
      end

      def visit_regexp_content(node)
        {
          type: :regexp_content,
          beging: node.beginning,
          parts: visit_all(node.parts),
          loc: visit_location(node.location)
        }
      end

      def visit_regexp_end(node)
        visit_token(:regexp_end, node)
      end

      def visit_regexp_literal(node)
        {
          type: :regexp_literal,
          beging: node.beginning,
          ending: node.ending,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_rescue(node)
        {
          type: :rescue,
          extn: visit(node.exception),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_rescue_ex(node)
        {
          type: :rescue_ex,
          extns: visit(node.exceptions),
          var: visit(node.variable),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_rescue_mod(node)
        {
          type: :rescue_mod,
          stmt: visit(node.statement),
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_rest_param(node)
        {
          type: :rest_param,
          name: visit(node.name),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_retry(node)
        visit_token(:retry, node)
      end

      def visit_return(node)
        {
          type: :return,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_return0(node)
        visit_token(:return0, node)
      end

      def visit_rparen(node)
        visit_token(:rparen, node)
      end

      def visit_sclass(node)
        {
          type: :sclass,
          target: visit(node.target),
          bodystmt: visit(node.bodystmt),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_statements(node)
        {
          type: :statements,
          body: visit_all(node.body),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_string_concat(node)
        {
          type: :string_concat,
          left: visit(node.left),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_string_content(node)
        {
          type: :string_content,
          parts: visit_all(node.parts),
          loc: visit_location(node.location)
        }
      end

      def visit_string_dvar(node)
        {
          type: :string_dvar,
          var: visit(node.variable),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_string_embexpr(node)
        {
          type: :string_embexpr,
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_string_literal(node)
        {
          type: :string_literal,
          parts: visit_all(node.parts),
          quote: node.quote,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_super(node)
        {
          type: :super,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_symbeg(node)
        visit_token(:symbeg, node)
      end

      def visit_symbol_content(node)
        {
          type: :symbol_content,
          value: visit(node.value),
          loc: visit_location(node.location)
        }
      end

      def visit_symbol_literal(node)
        {
          type: :symbol_literal,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_symbols(node)
        {
          type: :symbols,
          elems: visit_all(node.elements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_symbols_beg(node)
        visit_token(:symbols_beg, node)
      end

      def visit_tlambda(node)
        visit_token(:tlambda, node)
      end

      def visit_tlambeg(node)
        visit_token(:tlambeg, node)
      end

      def visit_top_const_field(node)
        {
          type: :top_const_field,
          constant: visit(node.constant),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_top_const_ref(node)
        {
          type: :top_const_ref,
          constant: visit(node.constant),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_tstring_beg(node)
        visit_token(:tstring_beg, node)
      end

      def visit_tstring_content(node)
        visit_token(:tstring_content, node)
      end

      def visit_tstring_end(node)
        visit_token(:tstring_end, node)
      end

      def visit_unary(node)
        {
          type: :unary,
          op: node.operator,
          value: visit(node.statement),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_undef(node)
        {
          type: :undef,
          syms: visit_all(node.symbols),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_unless(node)
        {
          type: :unless,
          pred: visit(node.predicate),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_unless_mod(node)
        {
          type: :unless_mod,
          stmt: visit(node.statement),
          pred: visit(node.predicate),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_until(node)
        {
          type: :until,
          pred: visit(node.predicate),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_until_mod(node)
        {
          type: :until_mod,
          stmt: visit(node.statement),
          pred: visit(node.predicate),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_var_alias(node)
        {
          type: :var_alias,
          left: visit(node.left),
          right: visit(node.right),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_var_field(node)
        {
          type: :var_field,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_var_ref(node)
        {
          type: :var_ref,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_vcall(node)
        {
          type: :vcall,
          value: visit(node.value),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_void_stmt(node)
        {
          type: :void_stmt,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_when(node)
        {
          type: :when,
          args: visit(node.arguments),
          stmts: visit(node.statements),
          cons: visit(node.consequent),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_while(node)
        {
          type: :while,
          pred: visit(node.predicate),
          stmts: visit(node.statements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_while_mod(node)
        {
          type: :while_mod,
          stmt: visit(node.statement),
          pred: visit(node.predicate),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_word(node)
        {
          type: :word,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_words(node)
        {
          type: :words,
          elems: visit_all(node.elements),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_words_beg(node)
        visit_token(:words_beg, node)
      end

      def visit_xstring(node)
        {
          type: :xstring,
          parts: visit_all(node.parts),
          loc: visit_location(node.location)
        }
      end

      def visit_xstring_literal(node)
        {
          type: :xstring_literal,
          parts: visit_all(node.parts),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_yield(node)
        {
          type: :yield,
          args: visit(node.arguments),
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end

      def visit_yield0(node)
        visit_token(:yield0, node)
      end

      def visit_zsuper(node)
        visit_token(:zsuper, node)
      end

      def visit___end__(node)
        visit_token(:__end__, node)
      end

      private

      def visit_call_operator(operator)
        operator == :"::" ? :"::" : visit(operator)
      end

      def visit_location(location)
        [
          location.start_line,
          location.start_char,
          location.end_line,
          location.end_char
        ]
      end

      def visit_token(type, node)
        {
          type: type,
          value: node.value,
          loc: visit_location(node.location),
          cmts: visit_all(node.comments)
        }
      end
    end
  end
end
