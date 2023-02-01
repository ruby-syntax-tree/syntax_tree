# frozen_string_literal: true

module SyntaxTree
  module Translation
    # This visitor is responsible for converting the syntax tree produced by
    # Syntax Tree into the syntax tree produced by the whitequark/parser gem.
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
        s(
          :alias,
          [visit(node.left), visit(node.right)],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 5),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an ARefNode.
      def visit_aref(node)
        if ::Parser::Builders::Default.emit_index
          if node.index.nil?
            s(
              :index,
              [visit(node.collection)],
              source_map_index(
                begin_token:
                  source_range_find(
                    node.collection.location.end_char,
                    node.location.end_char,
                    "["
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          else
            s(
              :index,
              [visit(node.collection)].concat(visit_all(node.index.parts)),
              source_map_index(
                begin_token:
                  source_range_find(
                    node.collection.location.end_char,
                    node.index.location.start_char,
                    "["
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          end
        else
          if node.index.nil?
            s(
              :send,
              [visit(node.collection), :[]],
              source_map_send(
                selector:
                  source_range_find(
                    node.collection.location.end_char,
                    node.location.end_char,
                    "[]"
                  ),
                expression: source_range_node(node)
              )
            )
          else
            s(
              :send,
              [visit(node.collection), :[], *visit_all(node.index.parts)],
              source_map_send(
                selector:
                  source_range(
                    source_range_find(
                      node.collection.location.end_char,
                      node.index.location.start_char,
                      "["
                    ).begin_pos,
                    node.location.end_char
                  ),
                expression: source_range_node(node)
              )
            )
          end
        end
      end

      # Visit an ARefField node.
      def visit_aref_field(node)
        if ::Parser::Builders::Default.emit_index
          if node.index.nil?
            s(
              :indexasgn,
              [visit(node.collection)],
              source_map_index(
                begin_token:
                  source_range_find(
                    node.collection.location.end_char,
                    node.location.end_char,
                    "["
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          else
            s(
              :indexasgn,
              [visit(node.collection)].concat(visit_all(node.index.parts)),
              source_map_index(
                begin_token:
                  source_range_find(
                    node.collection.location.end_char,
                    node.index.location.start_char,
                    "["
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          end
        else
          if node.index.nil?
            s(
              :send,
              [visit(node.collection), :[]=],
              source_map_send(
                selector:
                  source_range_find(
                    node.collection.location.end_char,
                    node.location.end_char,
                    "[]"
                  ),
                expression: source_range_node(node)
              )
            )
          else
            s(
              :send,
              [visit(node.collection), :[]=].concat(
                visit_all(node.index.parts)
              ),
              source_map_send(
                selector:
                  source_range(
                    source_range_find(
                      node.collection.location.end_char,
                      node.index.location.start_char,
                      "["
                    ).begin_pos,
                    node.location.end_char
                  ),
                expression: source_range_node(node)
              )
            )
          end
        end
      end

      # Visit an ArgBlock node.
      def visit_arg_block(node)
        s(
          :block_pass,
          [visit(node.value)],
          source_map_operator(
            operator: source_range_length(node.location.start_char, 1),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an ArgStar node.
      def visit_arg_star(node)
        if stack[-3].is_a?(MLHSParen) && stack[-3].contents.is_a?(MLHS)
          case node.value
          when nil
            s(:restarg, [], nil)
          when Ident
            s(:restarg, [node.value.value.to_sym], nil)
          else
            s(:restarg, [node.value.value.value.to_sym], nil)
          end
        else
          s(
            :splat,
            node.value.nil? ? [] : [visit(node.value)],
            source_map_operator(
              operator: source_range_length(node.location.start_char, 1),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit an ArgsForward node.
      def visit_args_forward(_node)
        s(:forwarded_args, [], nil)
      end

      # Visit an ArrayLiteral node.
      def visit_array(node)
        s(
          :array,
          node.contents ? visit_all(node.contents.parts) : [],
          if node.lbracket.nil?
            source_map_collection(expression: source_range_node(node))
          else
            source_map_collection(
              begin_token: source_range_node(node.lbracket),
              end_token: source_range_length(node.location.end_char, -1),
              expression: source_range_node(node)
            )
          end
        )
      end

      # Visit an AryPtn node.
      def visit_aryptn(node)
        type = :array_pattern
        children = visit_all(node.requireds)

        if node.rest.is_a?(VarField)
          if !node.rest.value.nil?
            children << s(:match_rest, [visit(node.rest)], nil)
          elsif node.posts.empty? &&
                node.rest.location.start_char == node.rest.location.end_char
            # Here we have an implicit rest, as in [foo,]. parser has a specific
            # type for these patterns.
            type = :array_pattern_with_tail
          else
            children << s(:match_rest, [], nil)
          end
        end

        inner = s(type, children + visit_all(node.posts), nil)
        if node.constant
          s(:const_pattern, [visit(node.constant), inner], nil)
        else
          inner
        end
      end

      # Visit an Assign node.
      def visit_assign(node)
        target = visit(node.target)
        location =
          target
            .location
            .with_operator(
              source_range_find(
                node.target.location.end_char,
                node.value.location.start_char,
                "="
              )
            )
            .with_expression(source_range_node(node))

        s(target.type, target.children + [visit(node.value)], location)
      end

      # Visit an Assoc node.
      def visit_assoc(node)
        if node.value.nil?
          type = node.key.value.start_with?(/[A-Z]/) ? :const : :send

          s(
            :pair,
            [
              visit(node.key),
              s(type, [nil, node.key.value.chomp(":").to_sym], nil)
            ],
            nil
          )
        else
          s(
            :pair,
            [visit(node.key), visit(node.value)],
            source_map_operator(
              operator: source_range_length(node.key.location.end_char, -1),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit an AssocSplat node.
      def visit_assoc_splat(node)
        s(
          :kwsplat,
          [visit(node.value)],
          source_map_operator(
            operator: source_range_length(node.location.start_char, 2),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Backref node.
      def visit_backref(node)
        location = source_map(expression: source_range_node(node))

        if node.value.match?(/^\$\d+$/)
          s(:nth_ref, [node.value[1..].to_i], location)
        else
          s(:back_ref, [node.value.to_sym], location)
        end
      end

      # Visit a BareAssocHash node.
      def visit_bare_assoc_hash(node)
        s(
          if ::Parser::Builders::Default.emit_kwargs &&
               !stack[-2].is_a?(ArrayLiteral)
            :kwargs
          else
            :hash
          end,
          visit_all(node.assocs),
          source_map_collection(expression: source_range_node(node))
        )
      end

      # Visit a BEGINBlock node.
      def visit_BEGIN(node)
        s(
          :preexe,
          [visit(node.statements)],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 5),
            begin_token:
              source_range_find(
                node.location.start_char + 5,
                node.statements.location.start_char,
                "{"
              ),
            end_token: source_range_length(node.location.end_char, -1),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Begin node.
      def visit_begin(node)
        location =
          source_map_collection(
            begin_token: source_range_length(node.location.start_char, 5),
            end_token: source_range_length(node.location.end_char, -3),
            expression: source_range_node(node)
          )

        if node.bodystmt.empty?
          s(:kwbegin, [], location)
        elsif node.bodystmt.rescue_clause.nil? &&
              node.bodystmt.ensure_clause.nil? && node.bodystmt.else_clause.nil?
          child = visit(node.bodystmt.statements)

          s(:kwbegin, child.type == :begin ? child.children : [child], location)
        else
          s(:kwbegin, [visit(node.bodystmt)], location)
        end
      end

      # Visit a Binary node.
      def visit_binary(node)
        case node.operator
        when :|
          current = -2
          while stack[current].is_a?(Binary) && stack[current].operator == :|
            current -= 1
          end

          if stack[current].is_a?(In)
            s(:match_alt, [visit(node.left), visit(node.right)], nil)
          else
            visit(canonical_binary(node))
          end
        when :"=>", :"&&", :and, :"||", :or
          s(
            { "=>": :match_as, "&&": :and, "||": :or }.fetch(
              node.operator,
              node.operator
            ),
            [visit(node.left), visit(node.right)],
            source_map_operator(
              operator:
                source_range_find(
                  node.left.location.end_char,
                  node.right.location.start_char,
                  node.operator.to_s
                ),
              expression: source_range_node(node)
            )
          )
        when :=~
          if node.left.is_a?(RegexpLiteral) && node.left.parts.length == 1 &&
               node.left.parts.first.is_a?(TStringContent)
            s(
              :match_with_lvasgn,
              [visit(node.left), visit(node.right)],
              source_map_operator(
                operator:
                  source_range_find(
                    node.left.location.end_char,
                    node.right.location.start_char,
                    node.operator.to_s
                  ),
                expression: source_range_node(node)
              )
            )
          else
            visit(canonical_binary(node))
          end
        else
          visit(canonical_binary(node))
        end
      end

      # Visit a BlockArg node.
      def visit_blockarg(node)
        if node.name.nil?
          s(
            :blockarg,
            [nil],
            source_map_variable(expression: source_range_node(node))
          )
        else
          s(
            :blockarg,
            [node.name.value.to_sym],
            source_map_variable(
              name: source_range_node(node.name),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit a BlockVar node.
      def visit_block_var(node)
        shadowargs =
          node.locals.map { |local| s(:shadowarg, [local.value.to_sym], nil) }

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
                s(:procarg0, [s(:arg, [required.value.to_sym], nil)], nil)
              else
                s(:procarg0, visit(required).children, nil)
              end

            return s(:args, [procarg0] + shadowargs, nil)
          end
        end

        s(:args, visit(node.params).children + shadowargs, nil)
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

          inner = s(:rescue, children, nil)
        end

        if node.ensure_clause
          inner = s(:ensure, [inner] + visit(node.ensure_clause).children, nil)
        end

        inner
      end

      # Visit a Break node.
      def visit_break(node)
        s(:break, visit_all(node.arguments.parts), nil)
      end

      # Visit a CallNode node.
      def visit_call(node)
        visit_command_call(
          CommandCall.new(
            receiver: node.receiver,
            operator: node.operator,
            message: node.message,
            arguments: node.arguments,
            block: nil,
            location: node.location
          )
        )
      end

      # Visit a Case node.
      def visit_case(node)
        clauses = [node.consequent]
        while clauses.last && !clauses.last.is_a?(Else)
          clauses << clauses.last.consequent
        end

        else_token =
          if clauses.last.is_a?(Else)
            source_range_length(clauses.last.location.start_char, 4)
          end

        s(
          node.consequent.is_a?(In) ? :case_match : :case,
          [visit(node.value)] + clauses.map { |clause| visit(clause) },
          source_map_condition(
            keyword: source_range_length(node.location.start_char, 4),
            else_token: else_token,
            end_token: source_range_length(node.location.end_char, -3),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a CHAR node.
      def visit_CHAR(node)
        s(
          :str,
          [node.value[1..]],
          source_map_collection(
            begin_token: source_range_length(node.location.start_char, 1),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a ClassDeclaration node.
      def visit_class(node)
        operator =
          if node.superclass
            source_range_find(
              node.constant.location.end_char,
              node.superclass.location.start_char,
              "<"
            )
          end

        s(
          :class,
          [visit(node.constant), visit(node.superclass), visit(node.bodystmt)],
          source_map_definition(
            keyword: source_range_length(node.location.start_char, 5),
            operator: operator,
            name: source_range_node(node.constant),
            end_token: source_range_length(node.location.end_char, -3)
          ).with_expression(source_range_node(node))
        )
      end

      # Visit a Command node.
      def visit_command(node)
        visit_command_call(
          CommandCall.new(
            receiver: nil,
            operator: nil,
            message: node.message,
            arguments: node.arguments,
            block: node.block,
            location: node.location
          )
        )
      end

      # Visit a CommandCall node.
      def visit_command_call(node)
        children = [
          visit(node.receiver),
          node.message == :call ? :call : node.message.value.to_sym
        ]
        begin_token = nil
        end_token = nil

        case node.arguments
        when Args
          children += visit_all(node.arguments.parts)
        when ArgParen
          case node.arguments.arguments
          when nil
            # skip
          when ArgsForward
            children << visit(node.arguments.arguments)
          else
            children += visit_all(node.arguments.arguments.parts)
          end

          begin_token =
            source_range_length(node.arguments.location.start_char, 1)
          end_token = source_range_length(node.arguments.location.end_char, -1)
        end

        dot_bound =
          if node.arguments
            node.arguments.location.start_char
          elsif node.block
            node.block.location.start_char
          else
            node.location.end_char
          end

        call =
          s(
            if node.operator.is_a?(Op) && node.operator.value == "&."
              :csend
            else
              :send
            end,
            children,
            source_map_send(
              dot:
                if node.operator == :"::"
                  source_range_find(
                    node.receiver.location.end_char,
                    (
                      if node.message == :call
                        dot_bound
                      else
                        node.message.location.start_char
                      end
                    ),
                    "::"
                  )
                elsif node.operator
                  source_range_node(node.operator)
                end,
              begin_token: begin_token,
              end_token: end_token,
              selector:
                node.message == :call ? nil : source_range_node(node.message),
              expression: source_range_node(node)
            )
          )

        if node.block
          type, arguments = block_children(node.block)

          s(
            type,
            [call, arguments, visit(node.block.bodystmt)],
            source_map_collection(
              begin_token: source_range_node(node.block.opening),
              end_token:
                source_range_length(
                  node.location.end_char,
                  node.block.opening.is_a?(Kw) ? -3 : -1
                ),
              expression: source_range_node(node)
            )
          )
        else
          call
        end
      end

      # Visit a Const node.
      def visit_const(node)
        s(
          :const,
          [nil, node.value.to_sym],
          source_map_constant(
            name: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a ConstPathField node.
      def visit_const_path_field(node)
        if node.parent.is_a?(VarRef) && node.parent.value.is_a?(Kw) &&
             node.parent.value.value == "self" && node.constant.is_a?(Ident)
          s(:send, [visit(node.parent), :"#{node.constant.value}="], nil)
        else
          s(
            :casgn,
            [visit(node.parent), node.constant.value.to_sym],
            source_map_constant(
              double_colon:
                source_range_find(
                  node.parent.location.end_char,
                  node.constant.location.start_char,
                  "::"
                ),
              name: source_range_node(node.constant),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit a ConstPathRef node.
      def visit_const_path_ref(node)
        s(
          :const,
          [visit(node.parent), node.constant.value.to_sym],
          source_map_constant(
            double_colon:
              source_range_find(
                node.parent.location.end_char,
                node.constant.location.start_char,
                "::"
              ),
            name: source_range_node(node.constant),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a ConstRef node.
      def visit_const_ref(node)
        s(
          :const,
          [nil, node.constant.value.to_sym],
          source_map_constant(
            name: source_range_node(node.constant),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a CVar node.
      def visit_cvar(node)
        s(
          :cvar,
          [node.value.to_sym],
          source_map_variable(
            name: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a DefNode node.
      def visit_def(node)
        name = node.name.value.to_sym
        args =
          case node.params
          when Params
            child = visit(node.params)

            s(
              child.type,
              child.children,
              source_map_collection(expression: nil)
            )
          when Paren
            child = visit(node.params.contents)

            s(
              child.type,
              child.children,
              source_map_collection(
                begin_token:
                  source_range_length(node.params.location.start_char, 1),
                end_token:
                  source_range_length(node.params.location.end_char, -1),
                expression: source_range_node(node.params)
              )
            )
          else
            s(:args, [], source_map_collection(expression: nil))
          end

        if node.target
          target = node.target.is_a?(Paren) ? node.target.contents : node.target

          s(
            :defs,
            [visit(target), name, args, visit(node.bodystmt)],
            source_map_method_definition(
              keyword: source_range_length(node.location.start_char, 3),
              operator: source_range_node(node.operator),
              name: source_range_node(node.name),
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          )
        else
          s(
            :def,
            [name, args, visit(node.bodystmt)],
            source_map_method_definition(
              keyword: source_range_length(node.location.start_char, 3),
              name: source_range_node(node.name),
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit a Defined node.
      def visit_defined(node)
        paren_range = (node.location.start_char + 8)...node.location.end_char
        begin_token, end_token =
          if buffer.source[paren_range].include?("(")
            [
              source_range_find(paren_range.begin, paren_range.end, "("),
              source_range_length(node.location.end_char, -1)
            ]
          end

        s(
          :defined?,
          [visit(node.value)],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 8),
            begin_token: begin_token,
            end_token: end_token,
            expression: source_range_node(node)
          )
        )
      end

      # Visit a DynaSymbol node.
      def visit_dyna_symbol(node)
        location =
          if node.quote
            source_map_collection(
              begin_token:
                source_range_length(
                  node.location.start_char,
                  node.quote.length
                ),
              end_token: source_range_length(node.location.end_char, -1),
              expression: source_range_node(node)
            )
          else
            source_map_collection(expression: source_range_node(node))
          end

        if node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          s(:sym, ["\"#{node.parts.first.value}\"".undump.to_sym], location)
        else
          s(:dsym, visit_all(node.parts), location)
        end
      end

      # Visit an Else node.
      def visit_else(node)
        if node.statements.empty? && stack[-2].is_a?(Case)
          s(:empty_else, [], nil)
        else
          visit(node.statements)
        end
      end

      # Visit an Elsif node.
      def visit_elsif(node)
        else_token =
          case node.consequent
          when Elsif
            source_range_length(node.consequent.location.start_char, 5)
          when Else
            source_range_length(node.consequent.location.start_char, 4)
          end

        expression =
          source_range(
            node.location.start_char,
            node.statements.location.end_char - 1
          )

        s(
          :if,
          [
            visit(node.predicate),
            visit(node.statements),
            visit(node.consequent)
          ],
          source_map_condition(
            keyword: source_range_length(node.location.start_char, 5),
            else_token: else_token,
            expression: expression
          )
        )
      end

      # Visit an ENDBlock node.
      def visit_END(node)
        s(
          :postexe,
          [visit(node.statements)],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 3),
            begin_token:
              source_range_find(
                node.location.start_char + 3,
                node.statements.location.start_char,
                "{"
              ),
            end_token: source_range_length(node.location.end_char, -1),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an Ensure node.
      def visit_ensure(node)
        s(:ensure, [visit(node.statements)], nil)
      end

      # Visit a Field node.
      def visit_field(node)
        message =
          case stack[-2]
          when Assign, MLHS
            Ident.new(
              value: :"#{node.name.value}=",
              location: node.name.location
            )
          else
            node.name
          end

        visit_command_call(
          CommandCall.new(
            receiver: node.parent,
            operator: node.operator,
            message: message,
            arguments: nil,
            block: nil,
            location: node.location
          )
        )
      end

      # Visit a FloatLiteral node.
      def visit_float(node)
        operator =
          if %w[+ -].include?(buffer.source[node.location.start_char])
            source_range_length(node.location.start_char, 1)
          end

        s(
          :float,
          [node.value.to_f],
          source_map_operator(
            operator: operator,
            expression: source_range_node(node)
          )
        )
      end

      # Visit a FndPtn node.
      def visit_fndptn(node)
        make_match_rest = ->(child) do
          if child.is_a?(VarField) && child.value.nil?
            s(:match_rest, [], nil)
          else
            s(:match_rest, [visit(child)], nil)
          end
        end

        inner =
          s(
            :find_pattern,
            [
              make_match_rest[node.left],
              *visit_all(node.values),
              make_match_rest[node.right]
            ],
            nil
          )

        if node.constant
          s(:const_pattern, [visit(node.constant), inner], nil)
        else
          inner
        end
      end

      # Visit a For node.
      def visit_for(node)
        s(
          :for,
          [visit(node.index), visit(node.collection), visit(node.statements)],
          nil
        )
      end

      # Visit a GVar node.
      def visit_gvar(node)
        s(
          :gvar,
          [node.value.to_sym],
          source_map_variable(
            name: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a HashLiteral node.
      def visit_hash(node)
        s(
          :hash,
          visit_all(node.assocs),
          source_map_collection(
            begin_token: source_range_length(node.location.start_char, 1),
            end_token: source_range_length(node.location.end_char, -1),
            expression: source_range_node(node)
          )
        )
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
              .each { |line| heredoc_segments << s(:str, ["#{line}\n"], nil) }
          else
            heredoc_segments << visit(part)
          end
        end

        heredoc_segments.trim!

        if node.beginning.value.match?(/`\w+`\z/)
          s(:xstr, heredoc_segments.segments, nil)
        elsif heredoc_segments.segments.length > 1
          s(:dstr, heredoc_segments.segments, nil)
        elsif heredoc_segments.segments.empty?
          s(:dstr, [], nil)
        else
          heredoc_segments.segments.first
        end
      end

      # Visit a HshPtn node.
      def visit_hshptn(node)
        children =
          node.keywords.map do |(keyword, value)|
            next s(:pair, [visit(keyword), visit(value)], nil) if value

            case keyword
            when Label
              s(:match_var, [keyword.value.chomp(":").to_sym], nil)
            when StringContent
              raise if keyword.parts.length > 1
              s(:match_var, [keyword.parts.first.value.to_sym], nil)
            end
          end

        if node.keyword_rest.is_a?(VarField)
          children << if node.keyword_rest.value.nil?
            s(:match_rest, [], nil)
          elsif node.keyword_rest.value == :nil
            s(:match_nil_pattern, [], nil)
          else
            s(:match_rest, [visit(node.keyword_rest)], nil)
          end
        end

        inner = s(:hash_pattern, children, nil)
        if node.constant
          s(:const_pattern, [visit(node.constant), inner], nil)
        else
          inner
        end
      end

      # Visit an Ident node.
      def visit_ident(node)
        s(
          :lvar,
          [node.value.to_sym],
          source_map_variable(
            name: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an IfNode node.
      def visit_if(node)
        predicate =
          case node.predicate
          when RangeNode
            type =
              node.predicate.operator.value == ".." ? :iflipflop : :eflipflop
            s(type, visit(node.predicate).children, nil)
          when RegexpLiteral
            s(:match_current_line, [visit(node.predicate)], nil)
          when Unary
            if node.predicate.operator.value == "!" &&
                 node.predicate.statement.is_a?(RegexpLiteral)
              s(
                :send,
                [s(:match_current_line, [visit(node.predicate.statement)]), :!],
                nil
              )
            else
              visit(node.predicate)
            end
          else
            visit(node.predicate)
          end

        s(
          :if,
          [predicate, visit(node.statements), visit(node.consequent)],
          if node.modifier?
            source_map_keyword(
              keyword:
                source_range_find(
                  node.statements.location.end_char,
                  node.predicate.location.start_char,
                  "if"
                ),
              expression: source_range_node(node)
            )
          else
            else_token =
              case node.consequent
              when Elsif
                source_range_length(node.consequent.location.start_char, 5)
              when Else
                source_range_length(node.consequent.location.start_char, 4)
              end

            source_map_condition(
              keyword: source_range_length(node.location.start_char, 2),
              else_token: else_token,
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          end
        )
      end

      # Visit an IfOp node.
      def visit_if_op(node)
        s(
          :if,
          [visit(node.predicate), visit(node.truthy), visit(node.falsy)],
          nil
        )
      end

      # Visit an Imaginary node.
      def visit_imaginary(node)
        s(
          :complex,
          [
            # We have to do an eval here in order to get the value in case it's
            # something like 42ri. to_c will not give the right value in that
            # case. Maybe there's an API for this but I can't find it.
            eval(node.value)
          ],
          source_map_operator(expression: source_range_node(node))
        )
      end

      # Visit an In node.
      def visit_in(node)
        case node.pattern
        when IfNode
          s(
            :in_pattern,
            [
              visit(node.pattern.statements),
              s(:if_guard, [visit(node.pattern.predicate)], nil),
              visit(node.statements)
            ],
            nil
          )
        when UnlessNode
          s(
            :in_pattern,
            [
              visit(node.pattern.statements),
              s(:unless_guard, [visit(node.pattern.predicate)], nil),
              visit(node.statements)
            ],
            nil
          )
        else
          s(
            :in_pattern,
            [visit(node.pattern), nil, visit(node.statements)],
            nil
          )
        end
      end

      # Visit an Int node.
      def visit_int(node)
        operator =
          if %w[+ -].include?(buffer.source[node.location.start_char])
            source_range_length(node.location.start_char, 1)
          end

        s(
          :int,
          [node.value.to_i],
          source_map_operator(
            operator: operator,
            expression: source_range_node(node)
          )
        )
      end

      # Visit an IVar node.
      def visit_ivar(node)
        s(
          :ivar,
          [node.value.to_sym],
          source_map_variable(
            name: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Kw node.
      def visit_kw(node)
        location = source_map(expression: source_range_node(node))

        case node.value
        when "__FILE__"
          s(:str, [buffer.name], location)
        when "__LINE__"
          s(:int, [node.location.start_line + buffer.first_line - 1], location)
        when "__ENCODING__"
          if ::Parser::Builders::Default.emit_encoding
            s(:__ENCODING__, [], location)
          else
            s(:const, [s(:const, [nil, :Encoding], nil), :UTF_8], location)
          end
        else
          s(node.value.to_sym, [], location)
        end
      end

      # Visit a KwRestParam node.
      def visit_kwrest_param(node)
        if node.name.nil?
          s(
            :kwrestarg,
            [],
            source_map_variable(expression: source_range_node(node))
          )
        else
          s(
            :kwrestarg,
            [node.name.value.to_sym],
            source_map_variable(
              name: source_range_node(node.name),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit a Label node.
      def visit_label(node)
        s(
          :sym,
          [node.value.chomp(":").to_sym],
          source_map_collection(
            expression:
              source_range(node.location.start_char, node.location.end_char - 1)
          )
        )
      end

      # Visit a Lambda node.
      def visit_lambda(node)
        args = node.params.is_a?(LambdaVar) ? node.params : node.params.contents

        arguments = visit(args)
        child =
          if ::Parser::Builders::Default.emit_lambda
            s(:lambda, [], nil)
          else
            s(:send, [nil, :lambda], nil)
          end

        type = :block
        if args.empty? && (maximum = num_block_type(node.statements))
          type = :numblock
          arguments = maximum
        end

        s(type, [child, arguments, visit(node.statements)], nil)
      end

      # Visit a LambdaVar node.
      def visit_lambda_var(node)
        shadowargs =
          node.locals.map { |local| s(:shadowarg, [local.value.to_sym], nil) }

        s(:args, visit(node.params).children + shadowargs, nil)
      end

      # Visit an MAssign node.
      def visit_massign(node)
        s(
          :masgn,
          [visit(node.target), visit(node.value)],
          source_map_operator(
            operator:
              source_range_find(
                node.target.location.end_char,
                node.value.location.start_char,
                "="
              ),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a MethodAddBlock node.
      def visit_method_add_block(node)
        type, arguments = block_children(node.block)

        case node.call
        when Break, Next, ReturnNode
          call = visit(node.call)
          s(
            call.type,
            [
              s(
                type,
                [*call.children, arguments, visit(node.block.bodystmt)],
                nil
              )
            ],
            nil
          )
        else
          s(
            type,
            [visit(node.call), arguments, visit(node.block.bodystmt)],
            nil
          )
        end
      end

      # Visit an MLHS node.
      def visit_mlhs(node)
        s(
          :mlhs,
          node.parts.map do |part|
            part.is_a?(Ident) ? s(:arg, [part.value.to_sym], nil) : visit(part)
          end,
          source_map_collection(expression: source_range_node(node))
        )
      end

      # Visit an MLHSParen node.
      def visit_mlhs_paren(node)
        visit(node.contents)
      end

      # Visit a ModuleDeclaration node.
      def visit_module(node)
        s(
          :module,
          [visit(node.constant), visit(node.bodystmt)],
          source_map_definition(
            keyword: source_range_length(node.location.start_char, 6),
            name: source_range_node(node.constant),
            end_token: source_range_length(node.location.end_char, -3)
          ).with_expression(source_range_node(node))
        )
      end

      # Visit an MRHS node.
      def visit_mrhs(node)
        visit_array(
          ArrayLiteral.new(
            lbracket: nil,
            contents: Args.new(parts: node.parts, location: node.location),
            location: node.location
          )
        )
      end

      # Visit a Next node.
      def visit_next(node)
        s(
          :next,
          visit_all(node.arguments.parts),
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 4),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Not node.
      def visit_not(node)
        if node.statement.nil?
          begin_token = source_range_find(node.location.start_char, nil, "(")
          end_token = source_range_find(node.location.start_char, nil, ")")

          s(
            :send,
            [
              s(
                :begin,
                [],
                source_map_collection(
                  begin_token: begin_token,
                  end_token: end_token,
                  expression: begin_token.join(end_token)
                )
              ),
              :!
            ],
            source_map_send(
              selector: source_range_length(node.location.start_char, 3),
              expression: source_range_node(node)
            )
          )
        else
          begin_token, end_token =
            if node.parentheses?
              [
                source_range_find(
                  node.location.start_char + 3,
                  node.statement.location.start_char,
                  "("
                ),
                source_range_length(node.location.end_char, -1)
              ]
            end

          s(
            :send,
            [visit(node.statement), :!],
            source_map_send(
              begin_token: begin_token,
              end_token: end_token,
              selector: source_range_length(node.location.start_char, 3),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit an OpAssign node.
      def visit_opassign(node)
        location =
          source_map_variable(
            name: source_range_node(node.target),
            expression: source_range_node(node)
          ).with_operator(source_range_node(node.operator))

        case node.operator.value
        when "||="
          s(:or_asgn, [visit(node.target), visit(node.value)], location)
        when "&&="
          s(:and_asgn, [visit(node.target), visit(node.value)], location)
        else
          s(
            :op_asgn,
            [
              visit(node.target),
              node.operator.value.chomp("=").to_sym,
              visit(node.value)
            ],
            location
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
              s(
                :arg,
                [required.value.to_sym],
                source_map_variable(
                  name: source_range_node(required),
                  expression: source_range_node(required)
                )
              )
            end
          end

        children +=
          node.optionals.map do |(name, value)|
            s(
              :optarg,
              [name.value.to_sym, visit(value)],
              source_map_variable(
                name: source_range_node(name),
                expression:
                  source_range_node(name).join(source_range_node(value))
              ).with_operator(
                source_range_find(
                  name.location.end_char,
                  value.location.start_char,
                  "="
                )
              )
            )
          end

        if node.rest && !node.rest.is_a?(ExcessedComma)
          children << visit(node.rest)
        end

        children +=
          node.posts.map do |post|
            s(
              :arg,
              [post.value.to_sym],
              source_map_variable(
                name: source_range_node(post),
                expression: source_range_node(post)
              )
            )
          end

        children +=
          node.keywords.map do |(name, value)|
            key = name.value.chomp(":").to_sym

            if value
              s(
                :kwoptarg,
                [key, visit(value)],
                source_map_variable(
                  name:
                    source_range(
                      name.location.start_char,
                      name.location.end_char - 1
                    ),
                  expression:
                    source_range_node(name).join(source_range_node(value))
                )
              )
            else
              s(
                :kwarg,
                [key],
                source_map_variable(
                  name:
                    source_range(
                      name.location.start_char,
                      name.location.end_char - 1
                    ),
                  expression: source_range_node(name)
                )
              )
            end
          end

        case node.keyword_rest
        when nil, ArgsForward
          # do nothing
        when :nil
          children << s(:kwnilarg, [], nil)
        else
          children << visit(node.keyword_rest)
        end

        children << visit(node.block) if node.block

        if node.keyword_rest.is_a?(ArgsForward)
          if children.empty? && !::Parser::Builders::Default.emit_forward_arg
            return s(:forward_args, [], nil)
          end

          children.insert(
            node.requireds.length + node.optionals.length +
              node.keywords.length,
            s(:forward_arg, [], nil)
          )
        end

        s(:args, children, nil)
      end

      # Visit a Paren node.
      def visit_paren(node)
        if node.contents.nil? ||
             (
               node.contents.is_a?(Statements) &&
                 node.contents.body.length == 1 &&
                 node.contents.body.first.is_a?(VoidStmt)
             )
          s(:begin, [], nil)
        elsif stack[-2].is_a?(DefNode) && stack[-2].target.nil? &&
              stack[-2].target == node
          visit(node.contents)
        else
          child = visit(node.contents)
          if child.type == :begin
            child
          else
            s(
              :begin,
              [child],
              source_map_collection(
                begin_token: source_range_length(node.location.start_char, 1),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          end
        end
      end

      # Visit a PinnedBegin node.
      def visit_pinned_begin(node)
        s(:pin, [s(:begin, [visit(node.statement)], nil)], nil)
      end

      # Visit a PinnedVarRef node.
      def visit_pinned_var_ref(node)
        s(:pin, [visit(node.value)], nil)
      end

      # Visit a Program node.
      def visit_program(node)
        visit(node.statements)
      end

      # Visit a QSymbols node.
      def visit_qsymbols(node)
        parts =
          node.elements.map do |element|
            SymbolLiteral.new(value: element, location: element.location)
          end

        visit_array(
          ArrayLiteral.new(
            lbracket: node.beginning,
            contents: Args.new(parts: parts, location: node.location),
            location: node.location
          )
        )
      end

      # Visit a QWords node.
      def visit_qwords(node)
        visit_array(
          ArrayLiteral.new(
            lbracket: node.beginning,
            contents: Args.new(parts: node.elements, location: node.location),
            location: node.location
          )
        )
      end

      # Visit a RangeNode node.
      def visit_range(node)
        s(
          node.operator.value == ".." ? :irange : :erange,
          [visit(node.left), visit(node.right)],
          source_map_operator(
            operator: source_range_node(node.operator),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an RAssign node.
      def visit_rassign(node)
        s(
          node.operator.value == "=>" ? :match_pattern : :match_pattern_p,
          [visit(node.value), visit(node.pattern)],
          source_map_operator(
            operator: source_range_node(node.operator),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Rational node.
      def visit_rational(node)
        s(
          :rational,
          [node.value.to_r],
          source_map_operator(expression: source_range_node(node))
        )
      end

      # Visit a Redo node.
      def visit_redo(node)
        s(
          :redo,
          [],
          source_map_keyword(
            keyword: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a RegexpLiteral node.
      def visit_regexp_literal(node)
        s(
          :regexp,
          visit_all(node.parts).push(
            s(
              :regopt,
              node.ending.scan(/[a-z]/).sort.map(&:to_sym),
              source_map(
                expression:
                  source_range_length(
                    node.location.end_char,
                    -(node.ending.length - 1)
                  )
              )
            )
          ),
          source_map_collection(
            begin_token:
              source_range_length(
                node.location.start_char,
                node.beginning.length
              ),
            end_token:
              source_range_length(
                node.location.end_char - node.ending.length,
                1
              ),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Rescue node.
      def visit_rescue(node)
        exceptions =
          case node.exception&.exceptions
          when nil
            nil
          when VarRef
            s(:array, [visit(node.exception.exceptions)], nil)
          when MRHS
            s(:array, visit_all(node.exception.exceptions.parts), nil)
          else
            s(:array, [visit(node.exception.exceptions)], nil)
          end

        resbody =
          if node.exception.nil?
            s(:resbody, [nil, nil, visit(node.statements)], nil)
          elsif node.exception.variable.nil?
            s(:resbody, [exceptions, nil, visit(node.statements)], nil)
          else
            s(
              :resbody,
              [
                exceptions,
                visit(node.exception.variable),
                visit(node.statements)
              ],
              nil
            )
          end

        children = [resbody]
        if node.consequent
          children += visit(node.consequent).children
        else
          children << nil
        end

        s(:rescue, children, nil)
      end

      # Visit a RescueMod node.
      def visit_rescue_mod(node)
        keyword =
          source_range_find(
            node.statement.location.end_char,
            node.value.location.start_char,
            "rescue"
          )

        s(
          :rescue,
          [
            visit(node.statement),
            s(
              :resbody,
              [nil, nil, visit(node.value)],
              source_map_rescue_body(
                keyword: keyword,
                expression: keyword.join(source_range_node(node.value))
              )
            ),
            nil
          ],
          source_map_condition(expression: source_range_node(node))
        )
      end

      # Visit a RestParam node.
      def visit_rest_param(node)
        if node.name
          s(
            :restarg,
            [node.name.value.to_sym],
            source_map_variable(
              name: source_range_node(node.name),
              expression: source_range_node(node)
            )
          )
        else
          s(
            :restarg,
            [],
            source_map_variable(expression: source_range_node(node))
          )
        end
      end

      # Visit a Retry node.
      def visit_retry(node)
        s(
          :retry,
          [],
          source_map_keyword(
            keyword: source_range_node(node),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a ReturnNode node.
      def visit_return(node)
        s(
          :return,
          node.arguments ? visit_all(node.arguments.parts) : [],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 6),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an SClass node.
      def visit_sclass(node)
        s(
          :sclass,
          [visit(node.target), visit(node.bodystmt)],
          source_map_definition(
            keyword: source_range_length(node.location.start_char, 5),
            operator:
              source_range_find(
                node.location.start_char + 5,
                node.target.location.start_char,
                "<<"
              ),
            end_token: source_range_length(node.location.end_char, -3)
          ).with_expression(source_range_node(node))
        )
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
          s(
            :begin,
            visit_all(children),
            source_map_collection(
              expression:
                source_range(
                  children.first.location.start_char,
                  children.last.location.end_char
                )
            )
          )
        end
      end

      # Visit a StringConcat node.
      def visit_string_concat(node)
        visit_string_literal(
          StringLiteral.new(
            parts: [node.left, node.right],
            quote: nil,
            location: node.location
          )
        )
      end

      # Visit a StringContent node.
      def visit_string_content(node)
        # Can get here if you're inside a hash pattern, e.g., in "a": 1
        s(:sym, [node.parts.first.value.to_sym], nil)
      end

      # Visit a StringDVar node.
      def visit_string_dvar(node)
        visit(node.variable)
      end

      # Visit a StringEmbExpr node.
      def visit_string_embexpr(node)
        s(
          :begin,
          visit(node.statements).then { |child| child ? [child] : [] },
          source_map_collection(
            begin_token: source_range_length(node.location.start_char, 2),
            end_token: source_range_length(node.location.end_char, -1),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a StringLiteral node.
      def visit_string_literal(node)
        location =
          if node.quote
            source_map_collection(
              begin_token: source_range_length(node.location.start_char, 1),
              end_token: source_range_length(node.location.end_char, -1),
              expression: source_range_node(node)
            )
          else
            source_map_collection(expression: source_range_node(node))
          end

        if node.parts.empty?
          s(:str, [""], location)
        elsif node.parts.length == 1 && node.parts.first.is_a?(TStringContent)
          child = visit(node.parts.first)
          s(child.type, child.children, location)
        else
          s(:dstr, visit_all(node.parts), location)
        end
      end

      # Visit a Super node.
      def visit_super(node)
        if node.arguments.is_a?(Args)
          s(
            :super,
            visit_all(node.arguments.parts),
            source_map_keyword(
              keyword: source_range_node(node),
              expression: source_range_node(node)
            )
          )
        else
          case node.arguments.arguments
          when nil
            s(
              :super,
              [],
              source_map_keyword(
                keyword: source_range_length(node.location.start_char, 5),
                begin_token:
                  source_range_find(
                    node.location.start_char + 5,
                    node.location.end_char,
                    "("
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          when ArgsForward
            s(:super, [visit(node.arguments.arguments)], nil)
          else
            s(
              :super,
              visit_all(node.arguments.arguments.parts),
              source_map_keyword(
                keyword: source_range_length(node.location.start_char, 5),
                begin_token:
                  source_range_find(
                    node.location.start_char + 5,
                    node.location.end_char,
                    "("
                  ),
                end_token: source_range_length(node.location.end_char, -1),
                expression: source_range_node(node)
              )
            )
          end
        end
      end

      # Visit a SymbolLiteral node.
      def visit_symbol_literal(node)
        begin_token =
          if buffer.source[node.location.start_char] == ":"
            source_range_length(node.location.start_char, 1)
          end

        s(
          :sym,
          [node.value.value.to_sym],
          source_map_collection(
            begin_token: begin_token,
            expression: source_range_node(node)
          )
        )
      end

      # Visit a Symbols node.
      def visit_symbols(node)
        parts =
          node.elements.map do |element|
            part = element.parts.first

            if element.parts.length == 1 && part.is_a?(TStringContent)
              SymbolLiteral.new(value: part, location: part.location)
            else
              DynaSymbol.new(
                parts: element.parts,
                quote: nil,
                location: element.location
              )
            end
          end

        visit_array(
          ArrayLiteral.new(
            lbracket: node.beginning,
            contents: Args.new(parts: parts, location: node.location),
            location: node.location
          )
        )
      end

      # Visit a TopConstField node.
      def visit_top_const_field(node)
        s(
          :casgn,
          [
            s(
              :cbase,
              [],
              source_map(
                expression: source_range_length(node.location.start_char, 2)
              )
            ),
            node.constant.value.to_sym
          ],
          source_map_constant(
            double_colon: source_range_length(node.location.start_char, 2),
            name: source_range_node(node.constant),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a TopConstRef node.
      def visit_top_const_ref(node)
        s(
          :const,
          [
            s(
              :cbase,
              [],
              source_map(
                expression: source_range_length(node.location.start_char, 2)
              )
            ),
            node.constant.value.to_sym
          ],
          source_map_constant(
            double_colon: source_range_length(node.location.start_char, 2),
            name: source_range_node(node.constant),
            expression: source_range_node(node)
          )
        )
      end

      # Visit a TStringContent node.
      def visit_tstring_content(node)
        dumped = node.value.gsub(/([^[:ascii:]])/) { $1.dump[1...-1] }

        s(
          :str,
          ["\"#{dumped}\"".undump],
          source_map_collection(expression: source_range_node(node))
        )
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
          return(
            s(
              :send,
              [s(:begin, [s(type, visit(range).children, nil)], nil), :!],
              nil
            )
          )
        end

        visit(canonical_unary(node))
      end

      # Visit an Undef node.
      def visit_undef(node)
        s(
          :undef,
          visit_all(node.symbols),
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 5),
            expression: source_range_node(node)
          )
        )
      end

      # Visit an UnlessNode node.
      def visit_unless(node)
        predicate =
          case node.predicate
          when RegexpLiteral
            s(:match_current_line, [visit(node.predicate)], nil)
          when Unary
            if node.predicate.operator.value == "!" &&
                 node.predicate.statement.is_a?(RegexpLiteral)
              s(
                :send,
                [s(:match_current_line, [visit(node.predicate.statement)]), :!],
                nil
              )
            else
              visit(node.predicate)
            end
          else
            visit(node.predicate)
          end

        s(
          :if,
          [predicate, visit(node.consequent), visit(node.statements)],
          if node.modifier?
            source_map_keyword(
              keyword:
                source_range_find(
                  node.statements.location.end_char,
                  node.predicate.location.start_char,
                  "unless"
                ),
              expression: source_range_node(node)
            )
          else
            source_map_condition(
              keyword: source_range_length(node.location.start_char, 6),
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          end
        )
      end

      # Visit an UntilNode node.
      def visit_until(node)
        s(
          loop_post?(node) ? :until_post : :until,
          [visit(node.predicate), visit(node.statements)],
          if node.modifier?
            source_map_keyword(
              keyword:
                source_range_find(
                  node.statements.location.end_char,
                  node.predicate.location.start_char,
                  "until"
                ),
              expression: source_range_node(node)
            )
          else
            source_map_keyword(
              keyword: source_range_length(node.location.start_char, 5),
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          end
        )
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
          return(
            s(
              :match_var,
              [node.value.value.to_sym],
              source_map_variable(
                name: source_range_node(node),
                expression: source_range_node(node)
              )
            )
          )
        end

        case node.value
        when Const
          s(
            :casgn,
            [nil, node.value.value.to_sym],
            source_map_constant(
              name: source_range_node(node.value),
              expression: source_range_node(node)
            )
          )
        when CVar, GVar, Ident, IVar, VarRef
          s(
            {
              CVar => :cvasgn,
              GVar => :gvasgn,
              Ident => :lvasgn,
              IVar => :ivasgn,
              VarRef => :lvasgn
            }[
              node.value.class
            ],
            [node.value.value.to_sym],
            source_map_variable(
              name: source_range_node(node),
              expression: source_range_node(node)
            )
          )
        else
          s(:match_rest, [], nil)
        end
      end

      # Visit a VarRef node.
      def visit_var_ref(node)
        visit(node.value)
      end

      # Visit a VCall node.
      def visit_vcall(node)
        visit_command_call(
          CommandCall.new(
            receiver: nil,
            operator: nil,
            message: node.value,
            arguments: nil,
            block: nil,
            location: node.location
          )
        )
      end

      # Visit a When node.
      def visit_when(node)
        keyword = source_range_length(node.location.start_char, 4)

        s(
          :when,
          visit_all(node.arguments.parts) + [visit(node.statements)],
          source_map_keyword(
            keyword: keyword,
            expression:
              source_range(
                keyword.begin_pos,
                node.statements.location.end_char - 1
              )
          )
        )
      end

      # Visit a WhileNode node.
      def visit_while(node)
        s(
          loop_post?(node) ? :while_post : :while,
          [visit(node.predicate), visit(node.statements)],
          if node.modifier?
            source_map_keyword(
              keyword:
                source_range_find(
                  node.statements.location.end_char,
                  node.predicate.location.start_char,
                  "while"
                ),
              expression: source_range_node(node)
            )
          else
            source_map_keyword(
              keyword: source_range_length(node.location.start_char, 5),
              end_token: source_range_length(node.location.end_char, -3),
              expression: source_range_node(node)
            )
          end
        )
      end

      # Visit a Word node.
      def visit_word(node)
        visit_string_literal(
          StringLiteral.new(
            parts: node.parts,
            quote: nil,
            location: node.location
          )
        )
      end

      # Visit a Words node.
      def visit_words(node)
        visit_array(
          ArrayLiteral.new(
            lbracket: node.beginning,
            contents: Args.new(parts: node.elements, location: node.location),
            location: node.location
          )
        )
      end

      # Visit an XStringLiteral node.
      def visit_xstring_literal(node)
        s(
          :xstr,
          visit_all(node.parts),
          source_map_collection(
            begin_token: source_range_length(node.location.start_char, 1),
            end_token: source_range_length(node.location.end_char, -1),
            expression: source_range_node(node)
          )
        )
      end

      def visit_yield(node)
        case node.arguments
        when nil
          s(
            :yield,
            [],
            source_map_keyword(
              keyword: source_range_length(node.location.start_char, 5),
              expression: source_range_node(node)
            )
          )
        when Args
          s(
            :yield,
            visit_all(node.arguments.parts),
            source_map_keyword(
              keyword: source_range_length(node.location.start_char, 5),
              expression: source_range_node(node)
            )
          )
        else
          s(
            :yield,
            visit_all(node.arguments.contents.parts),
            source_map_keyword(
              keyword: source_range_length(node.location.start_char, 5),
              begin_token:
                source_range_length(node.arguments.location.start_char, 1),
              end_token: source_range_length(node.location.end_char, -1),
              expression: source_range_node(node)
            )
          )
        end
      end

      # Visit a ZSuper node.
      def visit_zsuper(node)
        s(
          :zsuper,
          [],
          source_map_keyword(
            keyword: source_range_length(node.location.start_char, 5),
            expression: source_range_node(node)
          )
        )
      end

      private

      def block_children(node)
        arguments = (node.block_var ? visit(node.block_var) : s(:args, [], nil))

        type = :block
        if !node.block_var && (maximum = num_block_type(node.bodystmt))
          type = :numblock
          arguments = maximum
        end

        [type, arguments]
      end

      # Convert a Unary node into a canonical CommandCall node.
      def canonical_unary(node)
        # For integers and floats with a leading + or -, parser represents them
        # as just their values with the signs attached.
        if %w[+ -].include?(node.operator) &&
             (node.statement.is_a?(Int) || node.statement.is_a?(FloatLiteral))
          return(
            node.statement.class.new(
              value: "#{node.operator}#{node.statement.value}",
              location: node.location
            )
          )
        end

        value = { "+" => "+@", "-" => "-@" }.fetch(node.operator, node.operator)
        length = node.operator.length

        CommandCall.new(
          receiver: node.statement,
          operator: nil,
          message:
            Op.new(
              value: value,
              location:
                Location.new(
                  start_line: node.location.start_line,
                  start_char: node.location.start_char,
                  start_column: node.location.start_column,
                  end_line: node.location.start_line,
                  end_char: node.location.start_char + length,
                  end_column: node.location.start_column + length
                )
            ),
          arguments: nil,
          block: nil,
          location: node.location
        )
      end

      # Convert a Binary node into a canonical CommandCall node.
      def canonical_binary(node)
        operator = node.operator.to_s

        start_char = node.left.location.end_char
        end_char = node.right.location.start_char

        index = buffer.source[start_char...end_char].index(operator)
        start_line =
          node.location.start_line +
            buffer.source[start_char...index].count("\n")
        start_column =
          index - (buffer.source[start_char...index].rindex("\n") || 0)

        op_location =
          Location.new(
            start_line: start_line,
            start_column: start_column,
            start_char: start_char + index,
            end_line: start_line,
            end_column: start_column + operator.length,
            end_char: start_char + index + operator.length
          )

        CommandCall.new(
          receiver: node.left,
          operator: nil,
          message: Op.new(value: operator, location: op_location),
          arguments:
            Args.new(parts: [node.right], location: node.right.location),
          block: nil,
          location: node.location
        )
      end

      # When you have a begin..end while or begin..end until, it's a special
      # kind of syntax that executes the block in a loop. In this case the
      # parser gem has a special node type for it.
      def loop_post?(node)
        node.modifier? && node.statements.is_a?(Statements) &&
          node.statements.body.length == 1 &&
          node.statements.body.first.is_a?(Begin)
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

      # This method comes almost directly from the parser gem and creates a new
      # parser gem node from the given s-expression. type is expected to be a
      # symbol, children is expected to be an array, and location is expected to
      # be a source map.
      def s(type, children, location)
        ::Parser::AST::Node.new(type, children, location: location)
      end

      # Constructs a plain source map just for an expression.
      def source_map(expression:)
        ::Parser::Source::Map.new(expression)
      end

      # Constructs a new source map for a collection.
      def source_map_collection(begin_token: nil, end_token: nil, expression:)
        ::Parser::Source::Map::Collection.new(
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a conditional expression.
      def source_map_condition(
        keyword: nil,
        begin_token: nil,
        else_token: nil,
        end_token: nil,
        expression:
      )
        ::Parser::Source::Map::Condition.new(
          keyword,
          begin_token,
          else_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a constant reference.
      def source_map_constant(double_colon: nil, name: nil, expression:)
        ::Parser::Source::Map::Constant.new(double_colon, name, expression)
      end

      # Constructs a new source map for a class definition.
      def source_map_definition(
        keyword: nil,
        operator: nil,
        name: nil,
        end_token: nil
      )
        ::Parser::Source::Map::Definition.new(
          keyword,
          operator,
          name,
          end_token
        )
      end

      # Construct a source map for an index operation.
      def source_map_index(begin_token: nil, end_token: nil, expression:)
        ::Parser::Source::Map::Index.new(begin_token, end_token, expression)
      end

      # Constructs a new source map for the use of a keyword.
      def source_map_keyword(
        keyword: nil,
        begin_token: nil,
        end_token: nil,
        expression:
      )
        ::Parser::Source::Map::Keyword.new(
          keyword,
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a method definition.
      def source_map_method_definition(
        keyword: nil,
        operator: nil,
        name: nil,
        end_token: nil,
        assignment: nil,
        expression:
      )
        ::Parser::Source::Map::MethodDefinition.new(
          keyword,
          operator,
          name,
          end_token,
          assignment,
          expression
        )
      end

      # Constructs a new source map for an operator.
      def source_map_operator(operator: nil, expression:)
        ::Parser::Source::Map::Operator.new(operator, expression)
      end

      # Constructs a source map for the body of a rescue clause.
      def source_map_rescue_body(
        keyword: nil,
        assoc: nil,
        begin_token: nil,
        expression:
      )
        ::Parser::Source::Map::RescueBody.new(
          keyword,
          assoc,
          begin_token,
          expression
        )
      end

      # Constructs a new source map for a method call.
      def source_map_send(
        dot: nil,
        selector: nil,
        begin_token: nil,
        end_token: nil,
        expression:
      )
        ::Parser::Source::Map::Send.new(
          dot,
          selector,
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a variable.
      def source_map_variable(name: nil, expression:)
        ::Parser::Source::Map::Variable.new(name, expression)
      end

      # Constructs a new source range from the given start and end offsets.
      def source_range(start_char, end_char)
        ::Parser::Source::Range.new(buffer, start_char, end_char)
      end

      # Constructs a new source range by finding the given needle in the given
      # range of the source.
      def source_range_find(start_char, end_char, needle)
        index = buffer.source[start_char...end_char].index(needle)
        unless index
          slice = buffer.source[start_char...end_char].inspect
          raise "Could not find #{needle.inspect} in #{slice}"
        end

        offset = start_char + index
        source_range(offset, offset + needle.length)
      end

      # Constructs a new source range from the given start offset and length.
      def source_range_length(start_char, length)
        if length > 0
          source_range(start_char, start_char + length)
        else
          source_range(start_char + length, start_char)
        end
      end

      # Constructs a new source range using the given node's location.
      def source_range_node(node)
        location = node.location
        source_range(location.start_char, location.end_char)
      end
    end
  end
end
