# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class NodeTest < Minitest::Test
    def self.guard_version(version)
      yield if Gem::Version.new(RUBY_VERSION) >= Gem::Version.new(version)
    end

    def test_BEGIN
      assert_node(BEGINBlock, "BEGIN {}")
    end

    def test_CHAR
      assert_node(CHAR, "?a")
    end

    def test_END
      assert_node(ENDBlock, "END {}")
    end

    def test___end__
      source = <<~SOURCE
        a + 1
        __END__
        content
      SOURCE

      at = location(lines: 2..2, chars: 6..14)
      assert_node(EndContent, source, at: at)
    end

    def test_alias
      assert_node(AliasNode, "alias left right")
    end

    def test_aref
      assert_node(ARef, "collection[index]")
    end

    def test_aref_field
      source = "collection[index] = value"

      at = location(chars: 0..17)
      assert_node(ARefField, source, at: at, &:target)
    end

    def test_arg_paren
      source = "method(argument)"

      at = location(chars: 6..16)
      assert_node(ArgParen, source, at: at, &:arguments)
    end

    def test_arg_paren_heredoc
      source = <<~SOURCE
        method(<<~ARGUMENT)
          value
        ARGUMENT
      SOURCE

      at = location(lines: 1..3, chars: 6..28)
      assert_node(ArgParen, source, at: at, &:arguments)
    end

    def test_args
      source = "method(first, second, third)"

      at = location(chars: 7..27)
      assert_node(Args, source, at: at) { |node| node.arguments.arguments }
    end

    def test_arg_block
      source = "method(argument, &block)"

      at = location(chars: 17..23)
      assert_node(ArgBlock, source, at: at) do |node|
        node.arguments.arguments.parts[1]
      end
    end

    guard_version("3.1.0") do
      def test_arg_block_anonymous
        source = <<~SOURCE
          def method(&)
            child_method(&)
          end
        SOURCE

        at = location(lines: 2..2, chars: 29..30)
        assert_node(ArgBlock, source, at: at) do |node|
          node.bodystmt.statements.body.first.arguments.arguments.parts[0]
        end
      end
    end

    def test_arg_star
      source = "method(prefix, *arguments, suffix)"

      at = location(chars: 15..25)
      assert_node(ArgStar, source, at: at) do |node|
        node.arguments.arguments.parts[1]
      end
    end

    guard_version("2.7.3") do
      def test_args_forward
        source = <<~SOURCE
          def get(...)
            request(:GET, ...)
          end
        SOURCE

        at = location(lines: 2..2, chars: 29..32)
        assert_node(ArgsForward, source, at: at) do |node|
          node.bodystmt.statements.body.first.arguments.arguments.parts.last
        end
      end
    end

    def test_array
      assert_node(ArrayLiteral, "[1]")
    end

    def test_aryptn
      source = <<~SOURCE
        case [1, 2, 3]
        in Container[Integer, *, Integer]
          'matched'
        end
      SOURCE

      at = location(lines: 2..2, chars: 18..47)
      assert_node(AryPtn, source, at: at) { |node| node.consequent.pattern }
    end

    def test_assign
      assert_node(Assign, "variable = value")
    end

    def test_assoc
      source = "{ key1: value1, key2: value2 }"

      at = location(chars: 2..14)
      assert_node(Assoc, source, at: at) { |node| node.assocs.first }
    end

    guard_version("3.1.0") do
      def test_assoc_no_value
        source = "{ key1:, key2: }"

        at = location(chars: 2..7)
        assert_node(Assoc, source, at: at) { |node| node.assocs.first }
      end
    end

    def test_assoc_splat
      source = "{ **pairs }"

      at = location(chars: 2..9)
      assert_node(AssocSplat, source, at: at) { |node| node.assocs.first }
    end

    def test_backref
      assert_node(Backref, "$1")
    end

    def test_backtick
      at = location(chars: 4..5)
      assert_node(Backtick, "def `() end", at: at, &:name)
    end

    def test_bare_assoc_hash
      source = "method(key1: value1, key2: value2)"

      at = location(chars: 7..33)
      assert_node(BareAssocHash, source, at: at) do |node|
        node.arguments.arguments.parts.first
      end
    end

    guard_version("3.1.0") do
      def test_pinned_begin
        source = <<~SOURCE
          case value
          in ^(expression)
          end
        SOURCE

        at = location(lines: 2..2, chars: 14..27, columns: 3..16)
        assert_node(PinnedBegin, source, at: at) do |node|
          node.consequent.pattern
        end
      end
    end

    def test_begin
      source = <<~SOURCE
        begin
          value
        end
      SOURCE

      assert_node(Begin, source)
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

      assert_node(Begin, source)
    end

    def test_binary
      assert_node(Binary, "collection << value")
    end

    def test_block_var
      source = <<~SOURCE
        method do |positional, optional = value, keyword:, &block; local|
        end
      SOURCE

      at = location(chars: 10..65)
      assert_node(BlockVar, source, at: at) { |node| node.block.block_var }
    end

    def test_blockarg
      source = "def method(&block); end"

      at = location(chars: 11..17)
      assert_node(BlockArg, source, at: at) do |node|
        node.params.contents.block
      end
    end

    guard_version("3.1.0") do
      def test_blockarg_anonymous
        source = "def method(&); end"

        at = location(chars: 11..12)
        assert_node(BlockArg, source, at: at) do |node|
          node.params.contents.block
        end
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
      assert_node(BodyStmt, source, at: at, &:bodystmt)
    end

    def test_brace_block
      source = "method { |variable| variable + 1 }"

      at = location(chars: 7..34)
      assert_node(BlockNode, source, at: at, &:block)
    end

    def test_break
      assert_node(Break, "break value")
    end

    def test_call
      assert_node(CallNode, "receiver.message")
    end

    def test_case
      source = <<~SOURCE
        case value
        when 1
          "one"
        end
      SOURCE

      assert_node(Case, source)
    end

    guard_version("3.0.0") do
      def test_rassign_in
        assert_node(RAssign, "value in pattern")
      end

      def test_rassign_rocket
        assert_node(RAssign, "value => pattern")
      end
    end

    def test_class
      assert_node(ClassDeclaration, "class Child < Parent; end")
    end

    def test_command
      assert_node(Command, "method argument")
    end

    def test_command_call
      assert_node(CommandCall, "object.method argument")
    end

    def test_comment
      assert_node(Comment, "# comment", at: location(chars: 0..8))
    end

    # This test is to ensure that comments get parsed and printed properly in
    # all of the visitors. We do this by checking against a node that we're sure
    # will have comments attached to it in order to exercise all of the various
    # comments methods on the visitors.
    def test_comment_attached
      source = <<~SOURCE
        def method # comment
        end
      SOURCE

      at = location(chars: 10..10)
      assert_node(Params, source, at: at, &:params)
    end

    def test_const
      assert_node(Const, "Constant", &:value)
    end

    def test_const_path_field
      source = "object::Const = value"

      at = location(chars: 0..13)
      assert_node(ConstPathField, source, at: at, &:target)
    end

    def test_const_path_ref
      assert_node(ConstPathRef, "object::Const")
    end

    def test_const_ref
      source = "class Container; end"

      at = location(chars: 6..15)
      assert_node(ConstRef, source, at: at, &:constant)
    end

    def test_cvar
      assert_node(CVar, "@@variable", &:value)
    end

    def test_def
      assert_node(DefNode, "def method(param) result end")
    end

    def test_def_paramless
      source = <<~SOURCE
        def method
        end
      SOURCE

      assert_node(DefNode, source)
    end

    guard_version("3.0.0") do
      def test_def_endless
        assert_node(DefNode, "def method = result")
      end
    end

    guard_version("3.1.0") do
      def test_def_endless_command
        assert_node(DefNode, "def method = result argument")
      end
    end

    def test_defined
      assert_node(Defined, "defined?(variable)")
    end

    def test_defs
      assert_node(DefNode, "def object.method(param) result end")
    end

    def test_defs_paramless
      source = <<~SOURCE
        def object.method
        end
      SOURCE

      assert_node(DefNode, source)
    end

    def test_do_block
      source = "method do |variable| variable + 1 end"

      at = location(chars: 7..37)
      assert_node(BlockNode, source, at: at, &:block)
    end

    def test_dot2
      assert_node(RangeNode, "1..3")
    end

    def test_dot3
      assert_node(RangeNode, "1...3")
    end

    def test_dyna_symbol
      assert_node(DynaSymbol, ':"#{variable}"')
    end

    def test_dyna_symbol_hash_key
      source = '{ "#{key}": value }'

      at = location(chars: 2..11)
      assert_node(DynaSymbol, source, at: at) { |node| node.assocs.first.key }
    end

    def test_else
      source = <<~SOURCE
        if value
        else
        end
      SOURCE

      at = location(lines: 2..3, chars: 9..17)
      assert_node(Else, source, at: at, &:consequent)
    end

    def test_elsif
      source = <<~SOURCE
        if first
        elsif second
        else
        end
      SOURCE

      at = location(lines: 2..4, chars: 9..30)
      assert_node(Elsif, source, at: at, &:consequent)
    end

    def test_embdoc
      source = <<~SOURCE
        =begin
        first line
        second line
        =end
      SOURCE

      assert_node(EmbDoc, source)
    end

    def test_ensure
      source = <<~SOURCE
        begin
        ensure
        end
      SOURCE

      at = location(lines: 2..3, chars: 6..16)
      assert_node(Ensure, source, at: at) { |node| node.bodystmt.ensure_clause }
    end

    def test_excessed_comma
      source = "proc { |x,| }"

      at = location(chars: 9..10)
      assert_node(ExcessedComma, source, at: at) do |node|
        node.block.block_var.params.rest
      end
    end

    def test_fcall
      assert_node(CallNode, "method(argument)")
    end

    def test_field
      source = "object.variable = value"

      at = location(chars: 0..15)
      assert_node(Field, source, at: at, &:target)
    end

    def test_float_literal
      assert_node(FloatLiteral, "1.0")
    end

    guard_version("3.0.0") do
      def test_fndptn
        source = <<~SOURCE
          case value
          in Container[*, 7, *]
          end
        SOURCE

        at = location(lines: 2..2, chars: 14..32)
        assert_node(FndPtn, source, at: at) { |node| node.consequent.pattern }
      end
    end

    def test_for
      assert_node(For, "for value in list do end")
    end

    def test_gvar
      assert_node(GVar, "$variable", &:value)
    end

    def test_hash
      assert_node(HashLiteral, "{ key => value }")
    end

    def test_heredoc
      source = <<~SOURCE
        <<~HEREDOC
          contents
        HEREDOC
      SOURCE

      at = location(lines: 1..3, chars: 0..22)
      assert_node(Heredoc, source, at: at)
    end

    def test_heredoc_beg
      source = <<~SOURCE
        <<~HEREDOC
          contents
        HEREDOC
      SOURCE

      at = location(chars: 0..11)
      assert_node(HeredocBeg, source, at: at, &:beginning)
    end

    def test_heredoc_end
      source = <<~SOURCE
        <<~HEREDOC
          contents
        HEREDOC
      SOURCE

      at = location(lines: 3..3, chars: 22..31, columns: 0..9)
      assert_node(HeredocEnd, source, at: at, &:ending)
    end

    def test_hshptn
      source = <<~SOURCE
        case value
        in Container[key:, **keys]
        end
      SOURCE

      at = location(lines: 2..2, chars: 14..36)
      assert_node(HshPtn, source, at: at) { |node| node.consequent.pattern }
    end

    def test_ident
      assert_node(Ident, "value", &:value)
    end

    def test_if
      assert_node(IfNode, "if value then else end")
    end

    def test_if_op
      assert_node(IfOp, "value ? true : false")
    end

    def test_if_mod
      assert_node(IfNode, "expression if predicate")
    end

    def test_imaginary
      assert_node(Imaginary, "1i")
    end

    def test_in
      source = <<~SOURCE
        case value
        in first
        in second
        end
      SOURCE

      at = location(lines: 2..4, chars: 11..33)
      assert_node(In, source, at: at, &:consequent)
    end

    def test_int
      assert_node(Int, "1")
    end

    def test_ivar
      assert_node(IVar, "@variable", &:value)
    end

    def test_kw
      at = location(chars: 1..3)
      assert_node(Kw, ":if", at: at, &:value)
    end

    def test_kwrest_param
      source = "def method(**kwargs) end"

      at = location(chars: 11..19)
      assert_node(KwRestParam, source, at: at) do |node|
        node.params.contents.keyword_rest
      end
    end

    def test_label
      source = "{ key: value }"

      at = location(chars: 2..6)
      assert_node(Label, source, at: at) { |node| node.assocs.first.key }
    end

    def test_lambda
      source = "->(value) { value * 2 }"

      assert_node(Lambda, source)
    end

    def test_lambda_do
      source = "->(value) do value * 2 end"

      assert_node(Lambda, source)
    end

    def test_lbrace
      source = "method {}"

      at = location(chars: 7..8)
      assert_node(LBrace, source, at: at) { |node| node.block.opening }
    end

    def test_lparen
      source = "(1 + 1)"

      at = location(chars: 0..1)
      assert_node(LParen, source, at: at, &:lparen)
    end

    def test_massign
      assert_node(MAssign, "first, second, third = value")
    end

    def test_method_add_block
      assert_node(MethodAddBlock, "method {}")
    end

    def test_mlhs
      source = "left, right = value"

      at = location(chars: 0..11)
      assert_node(MLHS, source, at: at, &:target)
    end

    def test_mlhs_add_post
      source = "left, *middle, right = values"

      at = location(chars: 0..20)
      assert_node(MLHS, source, at: at, &:target)
    end

    def test_mlhs_paren
      source = "(left, right) = value"

      at = location(chars: 0..13)
      assert_node(MLHSParen, source, at: at, &:target)
    end

    def test_module
      source = <<~SOURCE
        module Container
        end
      SOURCE

      assert_node(ModuleDeclaration, source)
    end

    def test_mrhs
      source = "values = first, second, third"

      at = location(chars: 9..29)
      assert_node(MRHS, source, at: at, &:value)
    end

    def test_mrhs_add_star
      source = "values = first, *rest"

      at = location(chars: 9..21)
      assert_node(MRHS, source, at: at, &:value)
    end

    def test_next
      assert_node(Next, "next(value)")
    end

    def test_op
      at = location(chars: 4..5)
      assert_node(Op, "def +(value) end", at: at, &:name)
    end

    def test_opassign
      assert_node(OpAssign, "variable += value")
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
      assert_node(Params, source, at: at) { |node| node.params.contents }
    end

    def test_params_posts
      source = "def method(*rest, post) end"

      at = location(chars: 11..22)
      assert_node(Params, source, at: at) { |node| node.params.contents }
    end

    def test_paren
      assert_node(Paren, "(1 + 2)")
    end

    def test_period
      at = location(chars: 6..7)
      assert_node(Period, "object.method", at: at, &:operator)
    end

    def test_program
      parser = SyntaxTree::Parser.new("variable")
      program = parser.parse
      refute(parser.error?)

      statements = program.statements.body
      assert_equal 1, statements.size
      assert_kind_of(VCall, statements.first)

      json = JSON.parse(program.to_json)
      io = StringIO.new
      PP.singleline_pp(program, io)

      assert_kind_of(Program, program)
      assert_equal(location(chars: 0..8), program.location)
      assert_equal("program", json["type"])
      assert_match(/^\(program.*\)$/, io.string)
    end

    def test_qsymbols
      assert_node(QSymbols, "%i[one two three]")
    end

    def test_qwords
      assert_node(QWords, "%w[one two three]")
    end

    def test_rational
      assert_node(RationalLiteral, "1r")
    end

    def test_redo
      assert_node(Redo, "redo")
    end

    def test_regexp_literal
      assert_node(RegexpLiteral, "/abc/")
    end

    def test_rescue_ex
      source = <<~SOURCE
        begin
        rescue Exception => exception
        end
      SOURCE

      at = location(lines: 2..2, chars: 13..35)
      assert_node(RescueEx, source, at: at) do |node|
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
      assert_node(Rescue, source, at: at) { |node| node.bodystmt.rescue_clause }
    end

    def test_rescue_mod
      assert_node(RescueMod, "expression rescue value")
    end

    def test_rest_param
      source = "def method(*rest) end"

      at = location(chars: 11..16)
      assert_node(RestParam, source, at: at) do |node|
        node.params.contents.rest
      end
    end

    def test_retry
      assert_node(Retry, "retry")
    end

    def test_return
      assert_node(ReturnNode, "return value")
    end

    def test_return0
      assert_node(ReturnNode, "return")
    end

    def test_sclass
      assert_node(SClass, "class << self; end")
    end

    def test_statements
      at = location(chars: 1..6)
      assert_node(Statements, "(value)", at: at, &:contents)
    end

    def test_string_concat
      source = <<~SOURCE
        'left' \
          'right'
      SOURCE

      assert_node(StringConcat, source)
    end

    def test_string_dvar
      at = location(chars: 1..11)
      assert_node(StringDVar, '"#@variable"', at: at) do |node|
        node.parts.first
      end
    end

    def test_string_embexpr
      source = '"#{variable}"'

      at = location(chars: 1..12)
      assert_node(StringEmbExpr, source, at: at) { |node| node.parts.first }
    end

    def test_string_literal
      assert_node(StringLiteral, "\"string\"")
    end

    def test_super
      assert_node(Super, "super value")
    end

    def test_symbol_literal
      assert_node(SymbolLiteral, ":symbol")
    end

    def test_symbols
      assert_node(Symbols, "%I[one two three]")
    end

    def test_top_const_field
      source = "::Constant = value"

      at = location(chars: 0..10)
      assert_node(TopConstField, source, at: at, &:target)
    end

    def test_top_const_ref
      assert_node(TopConstRef, "::Constant")
    end

    def test_tstring_content
      source = "\"string\""

      at = location(chars: 1..7)
      assert_node(TStringContent, source, at: at) { |node| node.parts.first }
    end

    def test_not
      assert_node(Not, "not(value)")
    end

    def test_unary
      assert_node(Unary, "+value")
    end

    def test_undef
      assert_node(Undef, "undef value")
    end

    def test_unless
      assert_node(UnlessNode, "unless value then else end")
    end

    def test_unless_mod
      assert_node(UnlessNode, "expression unless predicate")
    end

    def test_until
      assert_node(UntilNode, "until value do end")
    end

    def test_until_mod
      assert_node(UntilNode, "expression until predicate")
    end

    def test_var_alias
      assert_node(AliasNode, "alias $new $old")
    end

    def test_var_field
      at = location(chars: 0..8)
      assert_node(VarField, "variable = value", at: at, &:target)
    end

    guard_version("3.1.0") do
      def test_pinned_var_ref
        source = "foo in ^bar"
        at = location(chars: 8..11)

        assert_node(PinnedVarRef, source, at: at, &:pattern)
      end
    end

    def test_var_ref
      assert_node(VarRef, "true")
    end

    def test_vcall
      assert_node(VCall, "variable")
    end

    def test_void_stmt
      assert_node(VoidStmt, ";;", at: location(chars: 0..0))
    end

    def test_when
      source = <<~SOURCE
        case value
        when one then :one
        when two then :two
        end
      SOURCE

      at = location(lines: 2..4, chars: 11..52)
      assert_node(When, source, at: at, &:consequent)
    end

    def test_while
      assert_node(WhileNode, "while value do end")
    end

    def test_while_mod
      assert_node(WhileNode, "expression while predicate")
    end

    def test_word
      at = location(chars: 3..7)
      assert_node(Word, "%W[word]", at: at) { |node| node.elements.first }
    end

    def test_words
      assert_node(Words, "%W[one two three]")
    end

    def test_xstring_literal
      assert_node(XStringLiteral, "`ls`")
    end

    def test_xstring_heredoc
      source = <<~SOURCE
        <<~`HEREDOC`
          ls
        HEREDOC
      SOURCE

      at = location(lines: 1..3, chars: 0..18)
      assert_node(Heredoc, source, at: at)
    end

    def test_yield
      assert_node(YieldNode, "yield value")
    end

    def test_yield0
      assert_node(YieldNode, "yield")
    end

    def test_zsuper
      assert_node(ZSuper, "super")
    end

    def test_column_positions
      source = <<~SOURCE
        puts 'Hello'
        puts 'Goodbye'
      SOURCE

      at = location(lines: 2..2, chars: 13..27, columns: 0..14)
      assert_node(Command, source, at: at)
    end

    def test_multibyte_column_positions
      source = <<~SOURCE
        puts "Congrats"
        puts "🎉 🎉"
      SOURCE

      at = location(lines: 2..2, chars: 16..26, columns: 0..10)
      assert_node(Command, source, at: at)
    end

    def test_root_class_raises_not_implemented_errors
      {
        accept: [nil],
        child_nodes: [],
        deconstruct: [],
        deconstruct_keys: [[]],
        format: [nil]
      }.each do |method, arguments|
        assert_raises(NotImplementedError) do
          Node.new.public_send(method, *arguments)
        end
      end
    end

    private

    def location(lines: 1..1, chars: 0..0, columns: 0..0)
      Location.new(
        start_line: lines.begin,
        start_char: chars.begin,
        start_column: columns.begin,
        end_line: lines.end,
        end_char: chars.end,
        end_column: columns.end
      )
    end

    def assert_node(kind, source, at: nil)
      at ||=
        location(
          lines: 1..[1, source.count("\n")].max,
          chars: 0..source.chomp.size,
          columns: 0..source.chomp.size
        )

      # Parse the example, get the outputted parse tree, and assert that it was
      # able to successfully parse.
      parser = SyntaxTree::Parser.new(source)
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

      # Finally, test that this node responds to everything it should.
      assert_syntax_tree(node)
    end
  end
end
