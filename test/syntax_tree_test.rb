# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'syntax_tree'

require 'json'
require 'pp'
require 'minitest/autorun'

class SyntaxTree
  class SyntaxTreeTest < Minitest::Test
    # --------------------------------------------------------------------------
    # Tests for behavior
    # --------------------------------------------------------------------------

    def test_multibyte
      assign = SyntaxTree.parse('🎉 + 🎉').statements.body.first
      assert_equal(5, assign.location.end_char)
    end

    def test_parse_error
      assert_raises(ParseError) { SyntaxTree.parse('<>') }
    end

    def test_next_statement_start
      source = <<~SOURCE
        def method # comment
          expression
        end
      SOURCE

      bodystmt = SyntaxTree.parse(source).statements.body.first.bodystmt
      assert_equal(20, bodystmt.location.start_char)
    end

    def test_version
      refute_nil(VERSION)
    end

    # --------------------------------------------------------------------------
    # Tests for nodes
    # --------------------------------------------------------------------------

    def test_BEGIN
      assert_node(BEGINBlock, 'BEGIN', 'BEGIN {}')
    end

    def test_CHAR
      assert_node(CHAR, 'CHAR', '?a')
    end

    def test_END
      assert_node(ENDBlock, 'END', 'END {}')
    end

    def test___end__
      source = <<~SOURCE
        a + 1
        __END__
        content
      SOURCE

      at = location(lines: 2..2, chars: 6..14)
      assert_node(EndContent, '__end__', source, at: at)
    end

    def test_alias
      assert_node(Alias, 'alias', 'alias left right')
    end

    def test_aref
      assert_node(ARef, 'aref', 'collection[index]')
    end

    def test_aref_field
      source = 'collection[index] = value'

      at = location(chars: 0..17)
      assert_node(ARefField, 'aref_field', source, at: at, &:target)
    end

    def test_arg_paren
      source = 'method(argument)'

      at = location(chars: 6..16)
      assert_node(ArgParen, 'arg_paren', source, at: at, &:arguments)
    end

    def test_arg_paren_heredoc
      source = <<~SOURCE
        method(<<~ARGUMENT)
          value
        ARGUMENT
      SOURCE

      at = location(lines: 1..3, chars: 6..28)
      assert_node(ArgParen, 'arg_paren', source, at: at, &:arguments)
    end

    def test_args
      source = 'method(first, second, third)'

      at = location(chars: 7..27)
      assert_node(Args, 'args', source, at: at) do |node|
        node.arguments.arguments.arguments
      end
    end

    def test_args_add_block
      source = 'method(argument, &block)'

      at = location(chars: 7..23)
      assert_node(ArgsAddBlock, 'args_add_block', source, at: at) do |node|
        node.arguments.arguments
      end
    end

    def test_arg_star
      source = 'method(prefix, *arguments, suffix)'

      at = location(chars: 15..25)
      assert_node(ArgStar, 'arg_star', source, at: at) do |node|
        node.arguments.arguments.arguments.parts[1]
      end
    end

    def test_args_forward
      source = <<~SOURCE
        def get(...)
          request(:GET, ...)
        end
      SOURCE

      at = location(lines: 2..2, chars: 29..32)
      assert_node(ArgsForward, 'args_forward', source, at: at) do |node|
        node.bodystmt.statements.body.first.arguments.arguments.parts.last
      end
    end

    def test_array
      assert_node(ArrayLiteral, 'array', '[1]')
    end

    def test_aryptn
      source = <<~SOURCE
        case [1, 2, 3]
        in Container[Integer, *, Integer]
          'matched'
        end
      SOURCE

      at = location(lines: 2..2, chars: 18..47)
      assert_node(AryPtn, 'aryptn', source, at: at) do |node|
        node.consequent.pattern
      end
    end

    def test_assign
      assert_node(Assign, 'assign', 'variable = value')
    end

    def test_assoc
      source = '{ key1: value1, key2: value2 }'

      at = location(chars: 2..14)
      assert_node(Assoc, 'assoc', source, at: at) do |node|
        node.contents.assocs.first
      end
    end

    def test_assoc_splat
      source = '{ **pairs }'

      at = location(chars: 2..9)
      assert_node(AssocSplat, 'assoc_splat', source, at: at) do |node|
        node.contents.assocs.first
      end
    end

    def test_assoclist_from_args
      type = 'assoclist_from_args'
      source = '{ key1: value1, key2: value2 }'

      at = location(chars: 1..29)
      assert_node(AssocListFromArgs, type, source, at: at, &:contents)
    end

    def test_backref
      assert_node(Backref, 'backref', '$1')
    end

    def test_backtick
      at = location(chars: 4..5)
      assert_node(Backtick, 'backtick', 'def `() end', at: at, &:name)
    end

    def test_bare_assoc_hash
      source = 'method(key1: value1, key2: value2)'

      at = location(chars: 7..33)
      assert_node(BareAssocHash, 'bare_assoc_hash', source, at: at) do |node|
        node.arguments.arguments.arguments.parts.first
      end
    end

    def test_begin
      source = <<~SOURCE
        begin
          value
        end
      SOURCE

      assert_node(Begin, 'begin', source)
    end

    def test_begin_clauses
      source = <<~SOURCE
        begin
          begun
        rescue
          rescued
        else
          elsed
        ensure
          ensured
        end
      SOURCE

      assert_node(Begin, 'begin', source)
    end

    def test_binary
      assert_node(Binary, 'binary', 'collection << value')
    end

    def test_block_var
      source = <<~SOURCE
        method do |positional, optional = value, keyword:, &block; local|
        end
      SOURCE

      at = location(chars: 10..65)
      assert_node(BlockVar, 'block_var', source, at: at) do |node|
        node.block.block_var
      end
    end

    def test_blockarg
      source = 'def method(&block); end'

      at = location(chars: 11..17)
      assert_node(BlockArg, 'blockarg', source, at: at) do |node|
        node.params.contents.block
      end
    end

    def test_bodystmt
      source = <<~SOURCE
        begin
          begun
        rescue
          rescued
        else
          elsed
        ensure
          ensured
        end
      SOURCE

      at = location(lines: 9..9, chars: 5..64)
      assert_node(BodyStmt, 'bodystmt', source, at: at, &:bodystmt)
    end

    def test_brace_block
      source = 'method { |variable| variable + 1 }'

      at = location(chars: 7..34)
      assert_node(BraceBlock, 'brace_block', source, at: at, &:block)
    end

    def test_break
      assert_node(Break, 'break', 'break value')
    end

    def test_call
      assert_node(Call, 'call', 'receiver.message')
    end

    def test_case
      source = <<~SOURCE
        case value
        when 1
          "one"
        end
      SOURCE

      assert_node(Case, 'case', source)
    end

    def test_rassign_in
      assert_node(RAssign, 'rassign', 'value in pattern')
    end

    def test_rassign_rocket
      assert_node(RAssign, 'rassign', 'value => pattern')
    end

    def test_class
      assert_node(ClassDeclaration, 'class', 'class Child < Parent; end')
    end

    def test_command
      assert_node(Command, 'command', 'method argument')
    end

    def test_command_call
      assert_node(CommandCall, 'command_call', 'object.method argument')
    end

    def test_comment
      assert_node(Comment, 'comment', '# comment', at: location(chars: 0..8))
    end

    def test_const
      assert_node(Const, 'const', 'Constant', &:value)
    end

    def test_const_path_field
      source = 'object::Const = value'

      at = location(chars: 0..13)
      assert_node(ConstPathField, 'const_path_field', source, at: at, &:target)
    end

    def test_const_path_ref
      assert_node(ConstPathRef, 'const_path_ref', 'object::Const')
    end

    def test_const_ref
      source = 'class Container; end'

      at = location(chars: 6..15)
      assert_node(ConstRef, 'const_ref', source, at: at, &:constant)
    end

    def test_cvar
      assert_node(CVar, 'cvar', '@@variable', &:value)
    end

    def test_def
      assert_node(Def, 'def', 'def method(param) result end')
    end

    def test_def_paramless
      source = <<~SOURCE
        def method
        end
      SOURCE

      assert_node(Def, 'def', source)
    end

    def test_def_endless
      assert_node(DefEndless, 'def_endless', 'def method = result')
    end

    def test_defined
      assert_node(Defined, 'defined', 'defined?(variable)')
    end

    def test_defs
      assert_node(Defs, 'defs', 'def object.method(param) result end')
    end

    def test_defs_paramless
      source = <<~SOURCE
        def object.method
        end
      SOURCE

      assert_node(Defs, 'defs', source)
    end

    def test_do_block
      source = 'method do |variable| variable + 1 end'

      at = location(chars: 7..37)
      assert_node(DoBlock, 'do_block', source, at: at, &:block)
    end

    def test_dot2
      assert_node(Dot2, 'dot2', '1..3')
    end

    def test_dot3
      assert_node(Dot3, 'dot3', '1...3')
    end

    def test_dyna_symbol
      assert_node(DynaSymbol, 'dyna_symbol', ':"#{variable}"')
    end

    def test_dyna_symbol_hash_key
      source = '{ "#{key}": value }'

      at = location(chars: 2..11)
      assert_node(DynaSymbol, 'dyna_symbol', source, at: at) do |node|
        node.contents.assocs.first.key
      end
    end

    def test_else
      source = <<~SOURCE
        if value
        else
        end
      SOURCE

      at = location(lines: 2..3, chars: 9..17)
      assert_node(Else, 'else', source, at: at, &:consequent)
    end

    def test_elsif
      source = <<~SOURCE
        if first
        elsif second
        else
        end
      SOURCE

      at = location(lines: 2..4, chars: 9..30)
      assert_node(Elsif, 'elsif', source, at: at, &:consequent)
    end

    def test_embdoc
      source = <<~SOURCE
        =begin
        first line
        second line
        =end
      SOURCE

      assert_node(EmbDoc, 'embdoc', source)
    end

    def test_ensure
      source = <<~SOURCE
        begin
        ensure
        end
      SOURCE

      at = location(lines: 2..3, chars: 6..16)
      assert_node(Ensure, 'ensure', source, at: at) do |node|
        node.bodystmt.ensure_clause
      end
    end

    def test_excessed_comma
      source = 'proc { |x,| }'

      at = location(chars: 9..10)
      assert_node(ExcessedComma, 'excessed_comma', source, at: at) do |node|
        node.block.block_var.params.rest
      end
    end

    def test_fcall
      source = 'method(argument)'

      at = location(chars: 0..6)
      assert_node(FCall, 'fcall', source, at: at, &:call)
    end

    def test_field
      source = 'object.variable = value'

      at = location(chars: 0..15)
      assert_node(Field, 'field', source, at: at, &:target)
    end

    def test_float_literal
      assert_node(FloatLiteral, 'float', '1.0')
    end

    def test_fndptn
      source = <<~SOURCE
        case value
        in Container[*, 7, *]
        end
      SOURCE

      at = location(lines: 2..2, chars: 14..32)
      assert_node(FndPtn, 'fndptn', source, at: at) do |node|
        node.consequent.pattern
      end
    end

    def test_for
      assert_node(For, 'for', 'for value in list do end')
    end

    def test_gvar
      assert_node(GVar, 'gvar', '$variable', &:value)
    end

    def test_hash
      assert_node(HashLiteral, 'hash', '{ key => value }')
    end

    def test_heredoc
      source = <<~SOURCE
        <<~HEREDOC
          contents
        HEREDOC
      SOURCE

      at = location(lines: 1..3, chars: 0..22)
      assert_node(Heredoc, 'heredoc', source, at: at)
    end

    def test_heredoc_beg
      source = <<~SOURCE
        <<~HEREDOC
          contents
        HEREDOC
      SOURCE

      at = location(chars: 0..11)
      assert_node(HeredocBeg, 'heredoc_beg', source, at: at, &:beginning)
    end

    def test_hshptn
      source = <<~SOURCE
        case value
        in Container[key:, **keys]
        end
      SOURCE

      at = location(lines: 2..2, chars: 14..36)
      assert_node(HshPtn, 'hshptn', source, at: at) do |node|
        node.consequent.pattern
      end
    end

    def test_ident
      assert_node(Ident, 'ident', 'value', &:value)
    end

    def test_if
      assert_node(If, 'if', 'if value then else end')
    end

    def test_ifop
      assert_node(IfOp, 'ifop', 'value ? true : false')
    end

    def test_if_mod
      assert_node(IfMod, 'if_mod', 'expression if predicate')
    end

    def test_imaginary
      assert_node(Imaginary, 'imaginary', '1i')
    end

    def test_in
      source = <<~SOURCE
        case value
        in first
        in second
        end
      SOURCE

      at = location(lines: 2..4, chars: 11..33)
      assert_node(In, 'in', source, at: at, &:consequent)
    end

    def test_int
      assert_node(Int, 'int', '1')
    end

    def test_ivar
      assert_node(IVar, 'ivar', '@variable', &:value)
    end

    def test_kw
      at = location(chars: 1..3)
      assert_node(Kw, 'kw', ':if', at: at, &:value)
    end

    def test_kwrest_param
      source = 'def method(**kwargs) end'

      at = location(chars: 11..19)
      assert_node(KwRestParam, 'kwrest_param', source, at: at) do |node|
        node.params.contents.keyword_rest
      end
    end

    def test_label
      source = '{ key: value }'

      at = location(chars: 2..6)
      assert_node(Label, 'label', source, at: at) do |node|
        node.contents.assocs.first.key
      end
    end

    def test_lambda
      source = '->(value) { value * 2 }'

      assert_node(Lambda, 'lambda', source)
    end

    def test_lambda_do
      source = '->(value) do value * 2 end'

      assert_node(Lambda, 'lambda', source)
    end

    def test_lbrace
      source = 'method {}'

      at = location(chars: 7..8)
      assert_node(LBrace, 'lbrace', source, at: at) do |node|
        node.block.lbrace
      end
    end

    def test_lparen
      source = '(1 + 1)'

      at = location(chars: 0..1)
      assert_node(LParen, 'lparen', source, at: at, &:lparen)
    end

    def test_massign
      assert_node(MAssign, 'massign', 'first, second, third = value')
    end

    def test_method_add_arg
      assert_node(MethodAddArg, 'method_add_arg', 'method(argument)')
    end

    def test_method_add_block
      assert_node(MethodAddBlock, 'method_add_block', 'method {}')
    end

    def test_mlhs
      source = 'left, right = value'

      at = location(chars: 0..11)
      assert_node(MLHS, 'mlhs', source, at: at, &:target)
    end

    def test_mlhs_add_post
      source = 'left, *middle, right = values'

      at = location(chars: 0..20)
      assert_node(MLHS, 'mlhs', source, at: at, &:target)
    end

    def test_mlhs_paren
      source = '(left, right) = value'

      at = location(chars: 0..13)
      assert_node(MLHSParen, 'mlhs_paren', source, at: at, &:target)
    end

    def test_module
      source = <<~SOURCE
        module Container
        end
      SOURCE

      assert_node(ModuleDeclaration, 'module', source)
    end

    def test_mrhs
      source = 'values = first, second, third'

      at = location(chars: 9..29)
      assert_node(MRHS, 'mrhs', source, at: at, &:value)
    end

    def test_mrhs_add_star
      source = 'values = first, *rest'

      at = location(chars: 16..21)
      assert_node(MRHSAddStar, 'mrhs_add_star', source, at: at, &:value)
    end

    def test_next
      assert_node(Next, 'next', 'next(value)')
    end

    def test_op
      at = location(chars: 4..5)
      assert_node(Op, 'op', 'def +(value) end', at: at, &:name)
    end

    def test_opassign
      assert_node(OpAssign, 'opassign', 'variable += value')
    end

    def test_params
      source = <<~SOURCE
        def method(
          one, two,
          three = 3, four = 4,
          *five,
          six:, seven: 7,
          **eight,
          &nine
        ) end
      SOURCE

      at = location(lines: 2..7, chars: 11..93)
      assert_node(Params, 'params', source, at: at) do |node|
        node.params.contents
      end
    end

    def test_params_posts
      source = 'def method(*rest, post) end'

      at = location(chars: 11..22)
      assert_node(Params, 'params', source, at: at) do |node|
        node.params.contents
      end
    end

    def test_paren
      assert_node(Paren, 'paren', '(1 + 2)')
    end

    def test_period
      at = location(chars: 6..7)
      assert_node(Period, 'period', 'object.method', at: at, &:operator)
    end

    def test_program
      parser = SyntaxTree.new('variable')
      program = parser.parse
      refute(parser.error?)

      json = JSON.parse(program.to_json)
      io = StringIO.new
      PP.singleline_pp(program, io)

      assert_kind_of(Program, program)
      assert_equal(location(chars: 0..8), program.location)
      assert_equal('program', json['type'])
      assert_match(/^\(program.*\)$/, io.string)
    end

    def test_qsymbols
      assert_node(QSymbols, 'qsymbols', '%i[one two three]')
    end

    def test_qwords
      assert_node(QWords, 'qwords', '%w[one two three]')
    end

    def test_rational
      assert_node(RationalLiteral, 'rational', '1r')
    end

    def test_redo
      assert_node(Redo, 'redo', 'redo')
    end

    def test_regexp_literal
      assert_node(RegexpLiteral, 'regexp_literal', '/abc/')
    end

    def test_rescue_ex
      source = <<~SOURCE
        begin
        rescue Exception => exception
        end
      SOURCE

      at = location(lines: 2..2, chars: 13..35)
      assert_node(RescueEx, 'rescue_ex', source, at: at) do |node|
        node.bodystmt.rescue_clause.exception
      end
    end

    def test_rescue
      source = <<~SOURCE
        begin
        rescue First
        rescue Second, Third
        rescue *Fourth
        end
      SOURCE

      at = location(lines: 2..5, chars: 6..58)
      assert_node(Rescue, 'rescue', source, at: at) do |node|
        node.bodystmt.rescue_clause
      end
    end

    def test_rescue_mod
      assert_node(RescueMod, 'rescue_mod', 'expression rescue value')
    end

    def test_rest_param
      source = 'def method(*rest) end'

      at = location(chars: 11..16)
      assert_node(RestParam, 'rest_param', source, at: at) do |node|
        node.params.contents.rest
      end
    end

    def test_retry
      assert_node(Retry, 'retry', 'retry')
    end

    def test_return
      assert_node(Return, 'return', 'return value')
    end

    def test_return0
      assert_node(Return0, 'return0', 'return')
    end

    def test_sclass
      assert_node(SClass, 'sclass', 'class << self; end')
    end

    def test_statements
      at = location(chars: 1..6)
      assert_node(Statements, 'statements', '(value)', at: at, &:contents)
    end

    def test_string_concat
      source = <<~SOURCE
        'left' \
          'right'
      SOURCE

      assert_node(StringConcat, 'string_concat', source)
    end

    def test_string_dvar
      at = location(chars: 1..11)
      assert_node(StringDVar, 'string_dvar', '"#@variable"', at: at) do |node|
        node.parts.first
      end
    end

    def test_string_embexpr
      source = '"#{variable}"'

      at = location(chars: 1..12)
      assert_node(StringEmbExpr, 'string_embexpr', source, at: at) do |node|
        node.parts.first
      end
    end

    def test_string_literal
      assert_node(StringLiteral, 'string_literal', '"string"')
    end

    def test_super
      assert_node(Super, 'super', 'super value')
    end

    def test_symbol_literal
      assert_node(SymbolLiteral, 'symbol_literal', ':symbol')
    end

    def test_symbols
      assert_node(Symbols, 'symbols', '%I[one two three]')
    end

    def test_top_const_field
      source = '::Constant = value'

      at = location(chars: 0..10)
      assert_node(TopConstField, 'top_const_field', source, at: at, &:target)
    end

    def test_top_const_ref
      assert_node(TopConstRef, 'top_const_ref', '::Constant')
    end

    def test_tstring_content
      source = '"string"'

      at = location(chars: 1..7)
      assert_node(TStringContent, 'tstring_content', source, at: at) do |node|
        node.parts.first
      end
    end

    def test_not
      assert_node(Not, 'not', 'not(value)')
    end

    def test_unary
      assert_node(Unary, 'unary', '+value')
    end

    def test_undef
      assert_node(Undef, 'undef', 'undef value')
    end

    def test_unless
      assert_node(Unless, 'unless', 'unless value then else end')
    end

    def test_unless_mod
      assert_node(UnlessMod, 'unless_mod', 'expression unless predicate')
    end

    def test_until
      assert_node(Until, 'until', 'until value do end')
    end

    def test_until_mod
      assert_node(UntilMod, 'until_mod', 'expression until predicate')
    end

    def test_var_alias
      assert_node(VarAlias, 'var_alias', 'alias $new $old')
    end

    def test_var_field
      at = location(chars: 0..8)
      assert_node(VarField, 'var_field', 'variable = value', at: at, &:target)
    end

    def test_var_ref
      assert_node(VarRef, 'var_ref', 'true')
    end

    def test_access_ctrl
      assert_node(AccessCtrl, 'access_ctrl', 'private')
    end

    def test_vcall
      assert_node(VCall, 'vcall', 'variable')
    end

    def test_void_stmt
      assert_node(VoidStmt, 'void_stmt', ';;', at: location(chars: 0..0))
    end

    def test_when
      source = <<~SOURCE
        case value
        when one then :one
        when two then :two
        end
      SOURCE

      at = location(lines: 2..4, chars: 11..52)
      assert_node(When, 'when', source, at: at, &:consequent)
    end

    def test_while
      assert_node(While, 'while', 'while value do end')
    end

    def test_while_mod
      assert_node(WhileMod, 'while_mod', 'expression while predicate')
    end

    def test_word
      at = location(chars: 3..7)
      assert_node(Word, 'word', '%W[word]', at: at) do |node|
        node.elements.first
      end
    end

    def test_words
      assert_node(Words, 'words', '%W[one two three]')
    end

    def test_xstring_literal
      assert_node(XStringLiteral, 'xstring_literal', '`ls`')
    end

    def test_xstring_heredoc
      source = <<~SOURCE
        <<~`HEREDOC`
          ls
        HEREDOC
      SOURCE

      at = location(lines: 1..3, chars: 0..18)
      assert_node(Heredoc, 'heredoc', source, at: at)
    end

    def test_yield
      assert_node(Yield, 'yield', 'yield value')
    end

    def test_yield0
      assert_node(Yield0, 'yield0', 'yield')
    end

    def test_zsuper
      assert_node(ZSuper, 'zsuper', 'super')
    end

    private

    def location(lines: 1..1, chars: 0..0)
      Location.new(
        start_line: lines.begin,
        start_char: chars.begin,
        end_line: lines.end,
        end_char: chars.end
      )
    end

    def assert_node(kind, type, source, at: nil)
      at ||=
        location(
          lines: 1..[1, source.count("\n")].max,
          chars: 0..source.chomp.size
        )

      # Parse the example, get the outputted parse tree, and assert that it was
      # able to successfully parse.
      parser = SyntaxTree.new(source)
      program = parser.parse
      refute(parser.error?)

      # Grab the last statement out of the parsed output. If a block is given,
      # then yield that statement so that the test can descend further down the
      # tree to get to the node it is testing.
      node = program.statements.body.last
      node = yield(node) if block_given?

      # Assert that the found node is the right type and that it has been found
      # at the expected location.
      assert_kind_of(kind, node)
      assert_equal(at, node.location)

      # Serialize the node to JSON, parse it back out, and assert that we have
      # found the expected type.
      json = JSON.parse(node.to_json)
      assert_equal(type, json['type'])

      # Pretty-print the node to a singleline and then assert that the top
      # s-expression of the printed output matches the expected type.
      io = StringIO.new
      PP.singleline_pp(node, io)
      assert_match(/^\(#{type}.*\)$/, io.string)
    end
  end
end
