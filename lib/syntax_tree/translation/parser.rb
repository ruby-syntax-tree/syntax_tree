# frozen_string_literal: true

module SyntaxTree
  module Translation
    class Parser < BasicVisitor
      attr_reader :buffer, :stack

      def initialize(buffer)
        @buffer = buffer
        @stack = []
      end

      # For each node that we visit, we keep track of it in a stack as we
      # descend into its children. We do this so that child nodes can reflect on
      # their parents if they need additional information about their context.
      def visit(node)
        stack << node
        result = super
        stack.pop
        result
      end

      # Visit an AliasNode node.
      def visit_alias(node)
        s(:alias, [visit(node.left), visit(node.right)])
      end

      # Visit an ARefNode.
      def visit_aref(node)
        if ::Parser::Builders::Default.emit_index
          if node.index.nil?
            s(:index, [visit(node.collection)])
          else
            s(:index, [visit(node.collection), *visit_all(node.index.parts)])
          end
        else
          if node.index.nil?
            s(:send, [visit(node.collection), :[], nil])
          else
            s(
              :send,
              [visit(node.collection), :[], *visit_all(node.index.parts)]
            )
          end
        end
      end

      # Visit an ARefField node.
      def visit_aref_field(node)
        if ::Parser::Builders::Default.emit_index
          if node.index.nil?
            s(:indexasgn, [visit(node.collection), nil])
          else
            s(
              :indexasgn,
              [visit(node.collection), *visit_all(node.index.parts)]
            )
          end
        else
          if node.index.nil?
            s(:send, [visit(node.collection), :[]=, nil])
          else
            s(
              :send,
              [visit(node.collection), :[]=, *visit_all(node.index.parts)]
            )
          end
        end
      end

      # Visit an ArgBlock node.
      def visit_arg_block(node)
        s(:block_pass, [visit(node.value)])
      end

      # Visit an ArgStar node.
      def visit_arg_star(node)
        if stack[-3].is_a?(MLHSParen) && stack[-3].contents.is_a?(MLHS)
          case node.value
          when nil
            s(:restarg)
          when Ident
            s(:restarg, [node.value.value.to_sym])
          else
            s(:restarg, [node.value.value.value.to_sym])
          end
        else
          node.value.nil? ? s(:splat) : s(:splat, [visit(node.value)])
        end
      end

      # Visit an ArgsForward node.
      def visit_args_forward(_node)
        s(:forwarded_args)
      end

      # Visit an ArrayLiteral node.
      def visit_array(node)
        if node.contents.nil?
          s(:array)
        else
          s(:array, visit_all(node.contents.parts))
        end
      end

      # Visit an AryPtn node.
      def visit_aryptn(node)
        type = :array_pattern
        children = visit_all(node.requireds)

        if node.rest.is_a?(VarField)
          if !node.rest.value.nil?
            children << s(:match_rest, [visit(node.rest)])
          elsif node.posts.empty? &&
                node.rest.location.start_char == node.rest.location.end_char
            # Here we have an implicit rest, as in [foo,]. parser has a specific
            # type for these patterns.
            type = :array_pattern_with_tail
          else
            children << s(:match_rest)
          end
        end

        inner = s(type, children + visit_all(node.posts))
        node.constant ? s(:const_pattern, [visit(node.constant), inner]) : inner
      end

      # Visit an Assign node.
      def visit_assign(node)
        target = visit(node.target)
        s(target.type, target.children + [visit(node.value)])
      end

      # Visit an Assoc node.
      def visit_assoc(node)
        if node.value.nil?
          type = node.key.value.start_with?(/[A-Z]/) ? :const : :send
          s(
            :pair,
            [visit(node.key), s(type, [nil, node.key.value.chomp(":").to_sym])]
          )
        else
          s(:pair, [visit(node.key), visit(node.value)])
        end
      end

      # Visit an AssocSplat node.
      def visit_assoc_splat(node)
        s(:kwsplat, [visit(node.value)])
      end

      # Visit a Backref node.
      def visit_backref(node)
        if node.value.match?(/^\$\d+$/)
          s(:nth_ref, [node.value[1..].to_i])
        else
          s(:back_ref, [node.value.to_sym])
        end
      end

      # Visit a BareAssocHash node.
      def visit_bare_assoc_hash(node)
        type =
          if ::Parser::Builders::Default.emit_kwargs &&
               !stack[-2].is_a?(ArrayLiteral)
            :kwargs
          else
            :hash
          end

        s(type, visit_all(node.assocs))
      end

      # Visit a BEGINBlock node.
      def visit_BEGIN(node)
        s(:preexe, [visit(node.statements)])
      end

      # Visit a Begin node.
      def visit_begin(node)
        if node.bodystmt.empty?
          s(:kwbegin)
        elsif node.bodystmt.rescue_clause.nil? &&
              node.bodystmt.ensure_clause.nil? && node.bodystmt.else_clause.nil?
          visited = visit(node.bodystmt.statements)
          s(:kwbegin, visited.type == :begin ? visited.children : [visited])
        else
          s(:kwbegin, [visit(node.bodystmt)])
        end
      end

      # Visit a Binary node.
      def visit_binary(node)
        case node.operator
        when :|
          current = -2
          current -= 1 while stack[current].is_a?(Binary) &&
            stack[current].operator == :|

          if stack[current].is_a?(In)
            s(:match_alt, [visit(node.left), visit(node.right)])
          else
            s(:send, [visit(node.left), node.operator, visit(node.right)])
          end
        when :"=>"
          s(:match_as, [visit(node.left), visit(node.right)])
        when :"&&", :and
          s(:and, [visit(node.left), visit(node.right)])
        when :"||", :or
          s(:or, [visit(node.left), visit(node.right)])
        when :=~
          if node.left.is_a?(RegexpLiteral) && node.left.parts.length == 1 &&
               node.left.parts.first.is_a?(TStringContent)
            s(:match_with_lvasgn, [visit(node.left), visit(node.right)])
          else
            s(:send, [visit(node.left), node.operator, visit(node.right)])
          end
        else
          s(:send, [visit(node.left), node.operator, visit(node.right)])
        end
      end

      # Visit a BlockArg node.
      def visit_blockarg(node)
        if node.name.nil?
          s(:blockarg, [nil])
        else
          s(:blockarg, [node.name.value.to_sym])
        end
      end

      # Visit a BlockVar node.
      def visit_block_var(node)
        shadowargs =
          node.locals.map { |local| s(:shadowarg, [local.value.to_sym]) }

        # There is a special node type in the parser gem for when a single
        # required parameter to a block would potentially be expanded
        # automatically. We handle that case here.
        if ::Parser::Builders::Default.emit_procarg0
          params = node.params

          if params.requireds.length == 1 && params.optionals.empty? &&
               params.rest.nil? && params.posts.empty? &&
               params.keywords.empty? && params.keyword_rest.nil? &&
               params.block.nil?
            required = params.requireds.first

            procarg0 =
              if ::Parser::Builders::Default.emit_arg_inside_procarg0 &&
                   required.is_a?(Ident)
                s(:procarg0, [s(:arg, [required.value.to_sym])])
              else
                s(:procarg0, visit(required).children)
              end

            return s(:args, [procarg0] + shadowargs)
          end
        end

        s(:args, visit(node.params).children + shadowargs)
      end

      # Visit a BodyStmt node.
      def visit_bodystmt(node)
        inner = visit(node.statements)

        if node.rescue_clause
          children = [inner] + visit(node.rescue_clause).children

          if node.else_clause
            children.pop
            children << visit(node.else_clause)
          end

          inner = s(:rescue, children)
        end

        if node.ensure_clause
          inner = s(:ensure, [inner] + visit(node.ensure_clause).children)
        end

        inner
      end

      # Visit a Break node.
      def visit_break(node)
        s(:break, visit_all(node.arguments.parts))
      end

      # Visit a CallNode node.
      def visit_call(node)
        if node.receiver.nil?
          children = [nil, node.message.value.to_sym]

          if node.arguments.is_a?(ArgParen)
            case node.arguments.arguments
            when nil
              # skip
            when ArgsForward
              children << s(:forwarded_args)
            else
              children += visit_all(node.arguments.arguments.parts)
            end
          end

          s(:send, children)
        elsif node.message == :call
          children = [visit(node.receiver), :call]

          unless node.arguments.arguments.nil?
            children += visit_all(node.arguments.arguments.parts)
          end

          s(send_type(node.operator), children)
        else
          children = [visit(node.receiver), node.message.value.to_sym]

          case node.arguments
          when Args
            children += visit_all(node.arguments.parts)
          when ArgParen
            unless node.arguments.arguments.nil?
              children += visit_all(node.arguments.arguments.parts)
            end
          end

          s(send_type(node.operator), children)
        end
      end

      # Visit a Case node.
      def visit_case(node)
        clauses = [node.consequent]
        while clauses.last && !clauses.last.is_a?(Else)
          clauses << clauses.last.consequent
        end

        type = node.consequent.is_a?(In) ? :case_match : :case
        s(type, [visit(node.value)] + clauses.map { |clause| visit(clause) })
      end

      # Visit a CHAR node.
      def visit_CHAR(node)
        s(:str, [node.value[1..]])
      end

      # Visit a ClassDeclaration node.
      def visit_class(node)
        s(
          :class,
          [visit(node.constant), visit(node.superclass), visit(node.bodystmt)]
        )
      end

      # Visit a Command node.
      def visit_command(node)
        call =
          s(
            :send,
            [nil, node.message.value.to_sym, *visit_all(node.arguments.parts)]
          )

        if node.block
          type, arguments = block_children(node.block)
          s(type, [call, arguments, visit(node.block.bodystmt)])
        else
          call
        end
      end

      # Visit a CommandCall node.
      def visit_command_call(node)
        children = [visit(node.receiver), node.message.value.to_sym]

        case node.arguments
        when Args
          children += visit_all(node.arguments.parts)
        when ArgParen
          children += visit_all(node.arguments.arguments.parts)
        end

        call = s(send_type(node.operator), children)

        if node.block
          type, arguments = block_children(node.block)
          s(type, [call, arguments, visit(node.block.bodystmt)])
        else
          call
        end
      end

      # Visit a Const node.
      def visit_const(node)
        s(:const, [nil, node.value.to_sym])
      end

      # Visit a ConstPathField node.
      def visit_const_path_field(node)
        if node.parent.is_a?(VarRef) && node.parent.value.is_a?(Kw) &&
             node.parent.value.value == "self" && node.constant.is_a?(Ident)
          s(:send, [visit(node.parent), :"#{node.constant.value}="])
        else
          s(:casgn, [visit(node.parent), node.constant.value.to_sym])
        end
      end

      # Visit a ConstPathRef node.
      def visit_const_path_ref(node)
        s(:const, [visit(node.parent), node.constant.value.to_sym])
      end

      # Visit a ConstRef node.
      def visit_const_ref(node)
        s(:const, [nil, node.constant.value.to_sym])
      end

      # Visit a CVar node.
      def visit_cvar(node)
        s(:cvar, [node.value.to_sym])
      end

      # Visit a DefNode node.
      def visit_def(node)
        name = node.name.value.to_sym
        args =
          case node.params
          when Params
            visit(node.params)
          when Paren
            visit(node.params.contents)
          else
            s(:args)
          end

        if node.target
          target = node.target.is_a?(Paren) ? node.target.contents : node.target
          s(:defs, [visit(target), name, args, visit(node.bodystmt)])
        else
          s(:def, [name, args, visit(node.bodystmt)])
        end
      end

      # Visit a Defined node.
      def visit_defined(node)
        s(:defined?, [visit(node.value)])
      end

      # Visit a DynaSymbol node.
      def visit_dyna_symbol(node)
        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          s(:sym, ["\"#{node.parts.first.value}\"".undump.to_sym])
        else
          s(:dsym, visit_all(node.parts))
        end
      end

      # Visit an Else node.
      def visit_else(node)
        if node.statements.empty? && stack[-2].is_a?(Case)
          s(:empty_else)
        else
          visit(node.statements)
        end
      end

      # Visit an Elsif node.
      def visit_elsif(node)
        s(
          :if,
          [
            visit(node.predicate),
            visit(node.statements),
            visit(node.consequent)
          ]
        )
      end

      # Visit an ENDBlock node.
      def visit_END(node)
        s(:postexe, [visit(node.statements)])
      end

      # Visit an Ensure node.
      def visit_ensure(node)
        s(:ensure, [visit(node.statements)])
      end

      # Visit a Field node.
      def visit_field(node)
        case stack[-2]
        when Assign, MLHS
          s(
            send_type(node.operator),
            [visit(node.parent), :"#{node.name.value}="]
          )
        else
          s(
            send_type(node.operator),
            [visit(node.parent), node.name.value.to_sym]
          )
        end
      end

      # Visit a FloatLiteral node.
      def visit_float(node)
        s(:float, [node.value.to_f])
      end

      # Visit a FndPtn node.
      def visit_fndptn(node)
        make_match_rest = ->(child) do
          if child.is_a?(VarField) && child.value.nil?
            s(:match_rest, [])
          else
            s(:match_rest, [visit(child)])
          end
        end

        inner =
          s(
            :find_pattern,
            [
              make_match_rest[node.left],
              *visit_all(node.values),
              make_match_rest[node.right]
            ]
          )
        node.constant ? s(:const_pattern, [visit(node.constant), inner]) : inner
      end

      # Visit a For node.
      def visit_for(node)
        s(
          :for,
          [visit(node.index), visit(node.collection), visit(node.statements)]
        )
      end

      # Visit a GVar node.
      def visit_gvar(node)
        s(:gvar, [node.value.to_sym])
      end

      # Visit a HashLiteral node.
      def visit_hash(node)
        s(:hash, visit_all(node.assocs))
      end

      # Heredocs are represented _very_ differently in the parser gem from how
      # they are represented in the Syntax Tree AST. This class is responsible
      # for handling the translation.
      class HeredocSegments
        HeredocLine = Struct.new(:value, :segments)

        attr_reader :node, :segments

        def initialize(node)
          @node = node
          @segments = []
        end

        def <<(segment)
          if segment.type == :str && segments.last &&
               segments.last.type == :str &&
               !segments.last.children.first.end_with?("\n")
            segments.last.children.first << segment.children.first
          else
            segments << segment
          end
        end

        def trim!
          return unless node.beginning.value[2] == "~"
          lines = [HeredocLine.new(+"", [])]

          segments.each do |segment|
            lines.last.segments << segment

            if segment.type == :str
              lines.last.value << segment.children.first

              if lines.last.value.end_with?("\n")
                lines << HeredocLine.new(+"", [])
              end
            end
          end

          lines.pop if lines.last.value.empty?
          return if lines.empty?

          segments.clear
          lines.each do |line|
            remaining = node.dedent

            line.segments.each do |segment|
              if segment.type == :str
                if remaining > 0
                  whitespace = segment.children.first[/^\s{0,#{remaining}}/]
                  segment.children.first.sub!(/^#{whitespace}/, "")
                  remaining -= whitespace.length
                end

                if node.beginning.value[3] != "'" && segments.any? &&
                     segments.last.type == :str &&
                     segments.last.children.first.end_with?("\\\n")
                  segments.last.children.first.gsub!(/\\\n\z/, "")
                  segments.last.children.first.concat(segment.children.first)
                elsif !segment.children.first.empty?
                  segments << segment
                end
              else
                segments << segment
              end
            end
          end
        end
      end

      # Visit a Heredoc node.
      def visit_heredoc(node)
        heredoc_segments = HeredocSegments.new(node)

        node.parts.each do |part|
          if part.is_a?(TStringContent) && part.value.count("\n") > 1
            part
              .value
              .split("\n")
              .each { |line| heredoc_segments << s(:str, ["#{line}\n"]) }
          else
            heredoc_segments << visit(part)
          end
        end

        heredoc_segments.trim!

        if node.beginning.value.match?(/`\w+`\z/)
          s(:xstr, heredoc_segments.segments)
        elsif heredoc_segments.segments.length > 1
          s(:dstr, heredoc_segments.segments)
        elsif heredoc_segments.segments.empty?
          s(:dstr)
        else
          heredoc_segments.segments.first
        end
      end

      # Visit a HshPtn node.
      def visit_hshptn(node)
        children =
          node.keywords.map do |(keyword, value)|
            next s(:pair, [visit(keyword), visit(value)]) if value

            case keyword
            when Label
              s(:match_var, [keyword.value.chomp(":").to_sym])
            when StringContent
              raise if keyword.parts.length > 1
              s(:match_var, [keyword.parts.first.value.to_sym])
            end
          end

        if node.keyword_rest.is_a?(VarField)
          children << if node.keyword_rest.value.nil?
            s(:match_rest)
          elsif node.keyword_rest.value == :nil
            s(:match_nil_pattern)
          else
            s(:match_rest, [visit(node.keyword_rest)])
          end
        end

        inner = s(:hash_pattern, children)
        node.constant ? s(:const_pattern, [visit(node.constant), inner]) : inner
      end

      # Visit an Ident node.
      def visit_ident(node)
        s(:lvar, [node.value.to_sym])
      end

      # Visit an IfNode node.
      def visit_if(node)
        predicate =
          case node.predicate
          when RangeNode
            type =
              node.predicate.operator.value == ".." ? :iflipflop : :eflipflop
            s(type, visit(node.predicate).children)
          when RegexpLiteral
            s(:match_current_line, [visit(node.predicate)])
          when Unary
            if node.predicate.operator.value == "!" &&
                 node.predicate.statement.is_a?(RegexpLiteral)
              s(
                :send,
                [s(:match_current_line, [visit(node.predicate.statement)]), :!]
              )
            else
              visit(node.predicate)
            end
          else
            visit(node.predicate)
          end

        s(:if, [predicate, visit(node.statements), visit(node.consequent)])
      end

      # Visit an IfOp node.
      def visit_if_op(node)
        s(:if, [visit(node.predicate), visit(node.truthy), visit(node.falsy)])
      end

      # Visit an Imaginary node.
      def visit_imaginary(node)
        # We have to do an eval here in order to get the value in case it's
        # something like 42ri. to_c will not give the right value in that case.
        # Maybe there's an API for this but I can't find it.
        s(:complex, [eval(node.value)])
      end

      # Visit an In node.
      def visit_in(node)
        case node.pattern
        when IfNode
          s(
            :in_pattern,
            [
              visit(node.pattern.statements),
              s(:if_guard, [visit(node.pattern.predicate)]),
              visit(node.statements)
            ]
          )
        when UnlessNode
          s(
            :in_pattern,
            [
              visit(node.pattern.statements),
              s(:unless_guard, [visit(node.pattern.predicate)]),
              visit(node.statements)
            ]
          )
        else
          s(:in_pattern, [visit(node.pattern), nil, visit(node.statements)])
        end
      end

      # Visit an Int node.
      def visit_int(node)
        s(:int, [node.value.to_i])
      end

      # Visit an IVar node.
      def visit_ivar(node)
        s(:ivar, [node.value.to_sym])
      end

      # Visit a Kw node.
      def visit_kw(node)
        case node.value
        when "__FILE__"
          s(:str, [buffer.name])
        when "__LINE__"
          s(:int, [node.location.start_line + buffer.first_line - 1])
        when "__ENCODING__"
          if ::Parser::Builders::Default.emit_encoding
            s(:__ENCODING__)
          else
            s(:const, [s(:const, [nil, :Encoding]), :UTF_8])
          end
        else
          s(node.value.to_sym)
        end
      end

      # Visit a KwRestParam node.
      def visit_kwrest_param(node)
        node.name.nil? ? s(:kwrestarg) : s(:kwrestarg, [node.name.value.to_sym])
      end

      # Visit a Label node.
      def visit_label(node)
        s(:sym, [node.value.chomp(":").to_sym])
      end

      # Visit a Lambda node.
      def visit_lambda(node)
        args = node.params.is_a?(LambdaVar) ? node.params : node.params.contents

        arguments = visit(args)
        child =
          if ::Parser::Builders::Default.emit_lambda
            s(:lambda)
          else
            s(:send, [nil, :lambda])
          end

        type = :block
        if args.empty? && (maximum = num_block_type(node.statements))
          type = :numblock
          arguments = maximum
        end

        s(type, [child, arguments, visit(node.statements)])
      end

      # Visit a LambdaVar node.
      def visit_lambda_var(node)
        shadowargs =
          node.locals.map { |local| s(:shadowarg, [local.value.to_sym]) }

        s(:args, visit(node.params).children + shadowargs)
      end

      # Visit an MAssign node.
      def visit_massign(node)
        s(:masgn, [visit(node.target), visit(node.value)])
      end

      # Visit a MethodAddBlock node.
      def visit_method_add_block(node)
        type, arguments = block_children(node.block)

        case node.call
        when Break, Next, ReturnNode
          call = visit(node.call)
          s(
            call.type,
            [s(type, [*call.children, arguments, visit(node.block.bodystmt)])]
          )
        else
          s(type, [visit(node.call), arguments, visit(node.block.bodystmt)])
        end
      end

      # Visit an MLHS node.
      def visit_mlhs(node)
        s(
          :mlhs,
          node.parts.map do |part|
            part.is_a?(Ident) ? s(:arg, [part.value.to_sym]) : visit(part)
          end
        )
      end

      # Visit an MLHSParen node.
      def visit_mlhs_paren(node)
        visit(node.contents)
      end

      # Visit a ModuleDeclaration node.
      def visit_module(node)
        s(:module, [visit(node.constant), visit(node.bodystmt)])
      end

      # Visit an MRHS node.
      def visit_mrhs(node)
        s(:array, visit_all(node.parts))
      end

      # Visit a Next node.
      def visit_next(node)
        s(:next, visit_all(node.arguments.parts))
      end

      # Visit a Not node.
      def visit_not(node)
        if node.statement.nil?
          s(:send, [s(:begin), :!])
        else
          s(:send, [visit(node.statement), :!])
        end
      end

      # Visit an OpAssign node.
      def visit_opassign(node)
        case node.operator.value
        when "||="
          s(:or_asgn, [visit(node.target), visit(node.value)])
        when "&&="
          s(:and_asgn, [visit(node.target), visit(node.value)])
        else
          s(
            :op_asgn,
            [
              visit(node.target),
              node.operator.value.chomp("=").to_sym,
              visit(node.value)
            ]
          )
        end
      end

      # Visit a Params node.
      def visit_params(node)
        children = []

        children +=
          node.requireds.map do |required|
            case required
            when MLHSParen
              visit(required)
            else
              s(:arg, [required.value.to_sym])
            end
          end

        children +=
          node.optionals.map do |(name, value)|
            s(:optarg, [name.value.to_sym, visit(value)])
          end
        if node.rest && !node.rest.is_a?(ExcessedComma)
          children << visit(node.rest)
        end
        children += node.posts.map { |post| s(:arg, [post.value.to_sym]) }
        children +=
          node.keywords.map do |(name, value)|
            key = name.value.chomp(":").to_sym
            value ? s(:kwoptarg, [key, visit(value)]) : s(:kwarg, [key])
          end

        case node.keyword_rest
        when nil, ArgsForward
          # do nothing
        when :nil
          children << s(:kwnilarg)
        else
          children << visit(node.keyword_rest)
        end

        children << visit(node.block) if node.block

        if node.keyword_rest.is_a?(ArgsForward)
          if children.empty? && !::Parser::Builders::Default.emit_forward_arg
            return s(:forward_args)
          end

          children.insert(
            node.requireds.length + node.optionals.length +
              node.keywords.length,
            s(:forward_arg)
          )
        end

        s(:args, children)
      end

      # Visit a Paren node.
      def visit_paren(node)
        if node.contents.nil? ||
             (
               node.contents.is_a?(Statements) &&
                 node.contents.body.length == 1 &&
                 node.contents.body.first.is_a?(VoidStmt)
             )
          s(:begin)
        elsif stack[-2].is_a?(DefNode) && stack[-2].target.nil? &&
              stack[-2].target == node
          visit(node.contents)
        else
          visited = visit(node.contents)
          visited.type == :begin ? visited : s(:begin, [visited])
        end
      end

      # Visit a PinnedBegin node.
      def visit_pinned_begin(node)
        s(:pin, [s(:begin, [visit(node.statement)])])
      end

      # Visit a PinnedVarRef node.
      def visit_pinned_var_ref(node)
        s(:pin, [visit(node.value)])
      end

      # Visit a Program node.
      def visit_program(node)
        visit(node.statements)
      end

      # Visit a QSymbols node.
      def visit_qsymbols(node)
        s(
          :array,
          node.elements.map { |element| s(:sym, [element.value.to_sym]) }
        )
      end

      # Visit a QWords node.
      def visit_qwords(node)
        s(:array, visit_all(node.elements))
      end

      # Visit a RangeNode node.
      def visit_range(node)
        type = node.operator.value == ".." ? :irange : :erange
        s(type, [visit(node.left), visit(node.right)])
      end

      # Visit an RAssign node.
      def visit_rassign(node)
        type = node.operator.value == "=>" ? :match_pattern : :match_pattern_p
        s(type, [visit(node.value), visit(node.pattern)])
      end

      # Visit a Rational node.
      def visit_rational(node)
        s(:rational, [node.value.to_r])
      end

      # Visit a Redo node.
      def visit_redo(_node)
        s(:redo)
      end

      # Visit a RegexpLiteral node.
      def visit_regexp_literal(node)
        s(
          :regexp,
          visit_all(node.parts) +
            [s(:regopt, node.ending.scan(/[a-z]/).sort.map(&:to_sym))]
        )
      end

      # Visit a Rescue node.
      def visit_rescue(node)
        exceptions =
          case node.exception&.exceptions
          when nil
            nil
          when VarRef
            s(:array, [visit(node.exception.exceptions)])
          when MRHS
            s(:array, visit_all(node.exception.exceptions.parts))
          else
            s(:array, [visit(node.exception.exceptions)])
          end

        resbody =
          if node.exception.nil?
            s(:resbody, [nil, nil, visit(node.statements)])
          elsif node.exception.variable.nil?
            s(:resbody, [exceptions, nil, visit(node.statements)])
          else
            s(
              :resbody,
              [
                exceptions,
                visit(node.exception.variable),
                visit(node.statements)
              ]
            )
          end

        children = [resbody]
        if node.consequent
          children += visit(node.consequent).children
        else
          children << nil
        end

        s(:rescue, children)
      end

      # Visit a RescueMod node.
      def visit_rescue_mod(node)
        s(
          :rescue,
          [
            visit(node.statement),
            s(:resbody, [nil, nil, visit(node.value)]),
            nil
          ]
        )
      end

      # Visit a RestParam node.
      def visit_rest_param(node)
        s(:restarg, node.name ? [node.name.value.to_sym] : [])
      end

      # Visit a Retry node.
      def visit_retry(_node)
        s(:retry)
      end

      # Visit a ReturnNode node.
      def visit_return(node)
        s(:return, node.arguments ? visit_all(node.arguments.parts) : [])
      end

      # Visit an SClass node.
      def visit_sclass(node)
        s(:sclass, [visit(node.target), visit(node.bodystmt)])
      end

      # Visit a Statements node.
      def visit_statements(node)
        children =
          node.body.reject do |child|
            child.is_a?(Comment) || child.is_a?(EmbDoc) ||
              child.is_a?(EndContent) || child.is_a?(VoidStmt)
          end

        case children.length
        when 0
          nil
        when 1
          visit(children.first)
        else
          s(:begin, visit_all(children))
        end
      end

      # Visit a StringConcat node.
      def visit_string_concat(node)
        s(:dstr, [visit(node.left), visit(node.right)])
      end

      # Visit a StringContent node.
      def visit_string_content(node)
        # Can get here if you're inside a hash pattern, e.g., in "a": 1
        s(:sym, [node.parts.first.value.to_sym])
      end

      # Visit a StringDVar node.
      def visit_string_dvar(node)
        visit(node.variable)
      end

      # Visit a StringEmbExpr node.
      def visit_string_embexpr(node)
        child = visit(node.statements)
        s(:begin, child ? [child] : [])
      end

      # Visit a StringLiteral node.
      def visit_string_literal(node)
        if node.parts.empty?
          s(:str, [""])
        elsif node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          visit(node.parts.first)
        else
          s(:dstr, visit_all(node.parts))
        end
      end

      # Visit a Super node.
      def visit_super(node)
        if node.arguments.is_a?(Args)
          s(:super, visit_all(node.arguments.parts))
        else
          case node.arguments.arguments
          when nil
            s(:super)
          when ArgsForward
            s(:super, [visit(node.arguments.arguments)])
          else
            s(:super, visit_all(node.arguments.arguments.parts))
          end
        end
      end

      # Visit a SymbolLiteral node.
      def visit_symbol_literal(node)
        s(:sym, [node.value.value.to_sym])
      end

      # Visit a Symbols node.
      def visit_symbols(node)
        children =
          node.elements.map do |element|
            if element.parts.length > 1 ||
                 !element.parts.first.is_a?(TStringContent)
              s(:dsym, visit_all(element.parts))
            else
              s(:sym, [element.parts.first.value.to_sym])
            end
          end

        s(:array, children)
      end

      # Visit a TopConstField node.
      def visit_top_const_field(node)
        s(:casgn, [s(:cbase), node.constant.value.to_sym])
      end

      # Visit a TopConstRef node.
      def visit_top_const_ref(node)
        s(:const, [s(:cbase), node.constant.value.to_sym])
      end

      # Visit a TStringContent node.
      def visit_tstring_content(node)
        value = node.value.gsub(/([^[:ascii:]])/) { $1.dump[1...-1] }
        s(:str, ["\"#{value}\"".undump])
      end

      # Visit a Unary node.
      def visit_unary(node)
        # Special handling here for flipflops
        if node.statement.is_a?(Paren) &&
             node.statement.contents.is_a?(Statements) &&
             node.statement.contents.body.length == 1 &&
             (range = node.statement.contents.body.first).is_a?(RangeNode) &&
             node.operator == "!"
          type = range.operator.value == ".." ? :iflipflop : :eflipflop
          return s(:send, [s(:begin, [s(type, visit(range).children)]), :!])
        end

        case node.operator
        when "+"
          case node.statement
          when Int
            s(:int, [node.statement.value.to_i])
          when FloatLiteral
            s(:float, [node.statement.value.to_f])
          else
            s(:send, [visit(node.statement), :+@])
          end
        when "-"
          case node.statement
          when Int
            s(:int, [-node.statement.value.to_i])
          when FloatLiteral
            s(:float, [-node.statement.value.to_f])
          else
            s(:send, [visit(node.statement), :-@])
          end
        else
          s(:send, [visit(node.statement), node.operator.to_sym])
        end
      end

      # Visit an Undef node.
      def visit_undef(node)
        s(:undef, visit_all(node.symbols))
      end

      # Visit an UnlessNode node.
      def visit_unless(node)
        predicate =
          case node.predicate
          when RegexpLiteral
            s(:match_current_line, [visit(node.predicate)])
          when Unary
            if node.predicate.operator.value == "!" &&
                 node.predicate.statement.is_a?(RegexpLiteral)
              s(
                :send,
                [s(:match_current_line, [visit(node.predicate.statement)]), :!]
              )
            else
              visit(node.predicate)
            end
          else
            visit(node.predicate)
          end

        s(:if, [predicate, visit(node.consequent), visit(node.statements)])
      end

      # Visit an UntilNode node.
      def visit_until(node)
        type =
          if node.modifier? && node.statements.is_a?(Statements) &&
               node.statements.body.length == 1 &&
               node.statements.body.first.is_a?(Begin)
            :until_post
          else
            :until
          end

        s(type, [visit(node.predicate), visit(node.statements)])
      end

      # Visit a VarField node.
      def visit_var_field(node)
        is_match_var = ->(parent) do
          case parent
          when AryPtn, FndPtn, HshPtn, In, RAssign
            true
          when Binary
            parent.operator == :"=>"
          else
            false
          end
        end

        if [stack[-3], stack[-2]].any?(&is_match_var)
          return s(:match_var, [node.value.value.to_sym])
        end

        case node.value
        when Const
          s(:casgn, [nil, node.value.value.to_sym])
        when CVar
          s(:cvasgn, [node.value.value.to_sym])
        when GVar
          s(:gvasgn, [node.value.value.to_sym])
        when Ident
          s(:lvasgn, [node.value.value.to_sym])
        when IVar
          s(:ivasgn, [node.value.value.to_sym])
        when VarRef
          s(:lvasgn, [node.value.value.to_sym])
        else
          s(:match_rest)
        end
      end

      # Visit a VarRef node.
      def visit_var_ref(node)
        visit(node.value)
      end

      # Visit a VCall node.
      def visit_vcall(node)
        range =
          ::Parser::Source::Range.new(
            buffer,
            node.location.start_char,
            node.location.end_char
          )
        location = ::Parser::Source::Map::Send.new(nil, range, nil, nil, range)

        s(:send, [nil, node.value.value.to_sym], location: location)
      end

      # Visit a When node.
      def visit_when(node)
        s(:when, visit_all(node.arguments.parts) + [visit(node.statements)])
      end

      # Visit a WhileNode node.
      def visit_while(node)
        type =
          if node.modifier? && node.statements.is_a?(Statements) &&
               node.statements.body.length == 1 &&
               node.statements.body.first.is_a?(Begin)
            :while_post
          else
            :while
          end

        s(type, [visit(node.predicate), visit(node.statements)])
      end

      # Visit a Word node.
      def visit_word(node)
        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          visit(node.parts.first)
        else
          s(:dstr, visit_all(node.parts))
        end
      end

      # Visit a Words node.
      def visit_words(node)
        s(:array, visit_all(node.elements))
      end

      # Visit an XStringLiteral node.
      def visit_xstring_literal(node)
        s(:xstr, visit_all(node.parts))
      end

      def visit_yield(node)
        case node.arguments
        when nil
          s(:yield)
        when Args
          s(:yield, visit_all(node.arguments.parts))
        else
          s(:yield, visit_all(node.arguments.contents.parts))
        end
      end

      # Visit a ZSuper node.
      def visit_zsuper(_node)
        s(:zsuper)
      end

      private

      def block_children(node)
        arguments = (node.block_var ? visit(node.block_var) : s(:args))

        type = :block
        if !node.block_var && (maximum = num_block_type(node.bodystmt))
          type = :numblock
          arguments = maximum
        end

        [type, arguments]
      end

      # We need to find if we should transform this block into a numblock
      # since there could be new numbered variables like _1.
      def num_block_type(statements)
        variables = []
        queue = [statements]

        while (child_node = queue.shift)
          if child_node.is_a?(VarRef) && child_node.value.is_a?(Ident) &&
               child_node.value.value =~ /^_(\d+)$/
            variables << $1.to_i
          end

          queue += child_node.child_nodes.compact
        end

        variables.max
      end

      def s(type, children = [], opts = {})
        ::Parser::AST::Node.new(type, children, opts)
      end

      def send_type(operator)
        operator.is_a?(Op) && operator.value == "&." ? :csend : :send
      end
    end
  end
end
