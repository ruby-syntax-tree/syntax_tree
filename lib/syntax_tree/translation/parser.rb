# frozen_string_literal: true

module SyntaxTree
  module Translation
    # This visitor is responsible for converting the syntax tree produced by
    # Syntax Tree into the syntax tree produced by the whitequark/parser gem.
    class Parser < BasicVisitor
      # Heredocs are represented _very_ differently in the parser gem from how
      # they are represented in the Syntax Tree AST. This class is responsible
      # for handling the translation.
      class HeredocBuilder
        Line = Struct.new(:value, :segments)

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
          lines = [Line.new(+"", [])]

          segments.each do |segment|
            lines.last.segments << segment

            if segment.type == :str
              lines.last.value << segment.children.first
              lines << Line.new(+"", []) if lines.last.value.end_with?("\n")
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

      visit_methods do
        # Visit an AliasNode node.
        def visit_alias(node)
          s(
            :alias,
            [visit(node.left), visit(node.right)],
            smap_keyword_bare(
              srange_length(node.start_char, 5),
              srange_node(node)
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
                smap_index(
                  srange_find(node.collection.end_char, node.end_char, "["),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            else
              s(
                :index,
                [visit(node.collection)].concat(visit_all(node.index.parts)),
                smap_index(
                  srange_find_between(node.collection, node.index, "["),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            end
          else
            if node.index.nil?
              s(
                :send,
                [visit(node.collection), :[]],
                smap_send_bare(
                  srange_find(node.collection.end_char, node.end_char, "[]"),
                  srange_node(node)
                )
              )
            else
              s(
                :send,
                [visit(node.collection), :[], *visit_all(node.index.parts)],
                smap_send_bare(
                  srange(
                    srange_find_between(
                      node.collection,
                      node.index,
                      "["
                    ).begin_pos,
                    node.end_char
                  ),
                  srange_node(node)
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
                smap_index(
                  srange_find(node.collection.end_char, node.end_char, "["),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            else
              s(
                :indexasgn,
                [visit(node.collection)].concat(visit_all(node.index.parts)),
                smap_index(
                  srange_find_between(node.collection, node.index, "["),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            end
          else
            if node.index.nil?
              s(
                :send,
                [visit(node.collection), :[]=],
                smap_send_bare(
                  srange_find(node.collection.end_char, node.end_char, "[]"),
                  srange_node(node)
                )
              )
            else
              s(
                :send,
                [visit(node.collection), :[]=].concat(
                  visit_all(node.index.parts)
                ),
                smap_send_bare(
                  srange(
                    srange_find_between(
                      node.collection,
                      node.index,
                      "["
                    ).begin_pos,
                    node.end_char
                  ),
                  srange_node(node)
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
            smap_operator(srange_length(node.start_char, 1), srange_node(node))
          )
        end

        # Visit an ArgStar node.
        def visit_arg_star(node)
          if stack[-3].is_a?(MLHSParen) && stack[-3].contents.is_a?(MLHS)
            if node.value.nil?
              s(:restarg, [], smap_variable(nil, srange_node(node)))
            else
              s(
                :restarg,
                [node.value.value.to_sym],
                smap_variable(srange_node(node.value), srange_node(node))
              )
            end
          else
            s(
              :splat,
              node.value.nil? ? [] : [visit(node.value)],
              smap_operator(
                srange_length(node.start_char, 1),
                srange_node(node)
              )
            )
          end
        end

        # Visit an ArgsForward node.
        def visit_args_forward(node)
          s(:forwarded_args, [], smap(srange_node(node)))
        end

        # Visit an ArrayLiteral node.
        def visit_array(node)
          s(
            :array,
            node.contents ? visit_all(node.contents.parts) : [],
            if node.lbracket.nil?
              smap_collection_bare(srange_node(node))
            else
              smap_collection(
                srange_node(node.lbracket),
                srange_length(node.end_char, -1),
                srange_node(node)
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
                  node.rest.start_char == node.rest.end_char
              # Here we have an implicit rest, as in [foo,]. parser has a
              # specific type for these patterns.
              type = :array_pattern_with_tail
            else
              children << s(:match_rest, [], nil)
            end
          end

          if node.constant
            s(
              :const_pattern,
              [
                visit(node.constant),
                s(
                  type,
                  children + visit_all(node.posts),
                  smap_collection_bare(
                    srange(node.constant.end_char + 1, node.end_char - 1)
                  )
                )
              ],
              smap_collection(
                srange_length(node.constant.end_char, 1),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
            )
          else
            s(
              type,
              children + visit_all(node.posts),
              if buffer.source[node.start_char] == "["
                smap_collection(
                  srange_length(node.start_char, 1),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              else
                smap_collection_bare(srange_node(node))
              end
            )
          end
        end

        # Visit an Assign node.
        def visit_assign(node)
          target = visit(node.target)
          location =
            target
              .location
              .with_operator(srange_find_between(node.target, node.value, "="))
              .with_expression(srange_node(node))

          s(target.type, target.children + [visit(node.value)], location)
        end

        # Visit an Assoc node.
        def visit_assoc(node)
          if node.value.nil?
            # { foo: }
            expression = srange(node.start_char, node.end_char - 1)
            type, location =
              if node.key.value.start_with?(/[A-Z]/)
                [:const, smap_constant(nil, expression, expression)]
              else
                [:send, smap_send_bare(expression, expression)]
              end

            s(
              :pair,
              [
                visit(node.key),
                s(type, [nil, node.key.value.chomp(":").to_sym], location)
              ],
              smap_operator(
                srange_length(node.key.end_char, -1),
                srange_node(node)
              )
            )
          elsif node.key.is_a?(Label)
            # { foo: 1 }
            s(
              :pair,
              [visit(node.key), visit(node.value)],
              smap_operator(
                srange_length(node.key.end_char, -1),
                srange_node(node)
              )
            )
          elsif (operator = srange_search_between(node.key, node.value, "=>"))
            # { :foo => 1 }
            s(
              :pair,
              [visit(node.key), visit(node.value)],
              smap_operator(operator, srange_node(node))
            )
          else
            # { "foo": 1 }
            key = visit(node.key)
            key_location =
              smap_collection(
                key.location.begin,
                srange_length(node.key.end_char - 2, 1),
                srange(node.key.start_char, node.key.end_char - 1)
              )

            s(
              :pair,
              [s(key.type, key.children, key_location), visit(node.value)],
              smap_operator(
                srange_length(node.key.end_char, -1),
                srange_node(node)
              )
            )
          end
        end

        # Visit an AssocSplat node.
        def visit_assoc_splat(node)
          s(
            :kwsplat,
            [visit(node.value)],
            smap_operator(srange_length(node.start_char, 2), srange_node(node))
          )
        end

        # Visit a Backref node.
        def visit_backref(node)
          location = smap(srange_node(node))

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
            smap_collection_bare(srange_node(node))
          )
        end

        # Visit a BEGINBlock node.
        def visit_BEGIN(node)
          s(
            :preexe,
            [visit(node.statements)],
            smap_keyword(
              srange_length(node.start_char, 5),
              srange_find(node.start_char + 5, node.statements.start_char, "{"),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit a Begin node.
        def visit_begin(node)
          location =
            smap_collection(
              srange_length(node.start_char, 5),
              srange_length(node.end_char, -3),
              srange_node(node)
            )

          if node.bodystmt.empty?
            s(:kwbegin, [], location)
          elsif node.bodystmt.rescue_clause.nil? &&
                node.bodystmt.ensure_clause.nil? &&
                node.bodystmt.else_clause.nil?
            child = visit(node.bodystmt.statements)

            s(
              :kwbegin,
              child.type == :begin ? child.children : [child],
              location
            )
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
              smap_operator(
                srange_find_between(node.left, node.right, node.operator.to_s),
                srange_node(node)
              )
            )
          when :=~
            # When you use a regular expression on the left hand side of a =~
            # operator and it doesn't have interpolatoin, then its named capture
            # groups introduce local variables into the scope. In this case the
            # parser gem has a different node (match_with_lvasgn) instead of the
            # regular send.
            if node.left.is_a?(RegexpLiteral) && node.left.parts.length == 1 &&
                 node.left.parts.first.is_a?(TStringContent)
              s(
                :match_with_lvasgn,
                [visit(node.left), visit(node.right)],
                smap_operator(
                  srange_find_between(
                    node.left,
                    node.right,
                    node.operator.to_s
                  ),
                  srange_node(node)
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
            s(:blockarg, [nil], smap_variable(nil, srange_node(node)))
          else
            s(
              :blockarg,
              [node.name.value.to_sym],
              smap_variable(srange_node(node.name), srange_node(node))
            )
          end
        end

        # Visit a BlockVar node.
        def visit_block_var(node)
          shadowargs =
            node.locals.map do |local|
              s(
                :shadowarg,
                [local.value.to_sym],
                smap_variable(srange_node(local), srange_node(local))
              )
            end

          params = node.params
          children =
            if ::Parser::Builders::Default.emit_procarg0 && node.arg0?
              # There is a special node type in the parser gem for when a single
              # required parameter to a block would potentially be expanded
              # automatically. We handle that case here.
              required = params.requireds.first
              procarg0 =
                if ::Parser::Builders::Default.emit_arg_inside_procarg0 &&
                     required.is_a?(Ident)
                  s(
                    :procarg0,
                    [
                      s(
                        :arg,
                        [required.value.to_sym],
                        smap_variable(
                          srange_node(required),
                          srange_node(required)
                        )
                      )
                    ],
                    smap_collection_bare(srange_node(required))
                  )
                else
                  child = visit(required)
                  s(:procarg0, child, child.location)
                end

              [procarg0]
            else
              visit(params).children
            end

          s(
            :args,
            children + shadowargs,
            smap_collection(
              srange_length(node.start_char, 1),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit a BodyStmt node.
        def visit_bodystmt(node)
          result = visit(node.statements)

          if node.rescue_clause
            rescue_node = visit(node.rescue_clause)

            children = [result] + rescue_node.children
            location = rescue_node.location

            if node.else_clause
              children.pop
              children << visit(node.else_clause)

              location =
                smap_condition(
                  nil,
                  nil,
                  srange_length(node.else_clause.start_char - 3, -4),
                  nil,
                  srange(
                    location.expression.begin_pos,
                    node.else_clause.end_char
                  )
                )
            end

            result = s(rescue_node.type, children, location)
          end

          if node.ensure_clause
            ensure_node = visit(node.ensure_clause)

            expression =
              (
                if result
                  result.location.expression.join(
                    ensure_node.location.expression
                  )
                else
                  ensure_node.location.expression
                end
              )
            location = ensure_node.location.with_expression(expression)

            result =
              s(ensure_node.type, [result] + ensure_node.children, location)
          end

          result
        end

        # Visit a Break node.
        def visit_break(node)
          s(
            :break,
            visit_all(node.arguments.parts),
            smap_keyword_bare(
              srange_length(node.start_char, 5),
              srange_node(node)
            )
          )
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
              srange_length(clauses.last.start_char, 4)
            end

          s(
            node.consequent.is_a?(In) ? :case_match : :case,
            [visit(node.value)] + clauses.map { |clause| visit(clause) },
            smap_condition(
              srange_length(node.start_char, 4),
              nil,
              else_token,
              srange_length(node.end_char, -3),
              srange_node(node)
            )
          )
        end

        # Visit a CHAR node.
        def visit_CHAR(node)
          s(
            :str,
            [node.value[1..]],
            smap_collection(
              srange_length(node.start_char, 1),
              nil,
              srange_node(node)
            )
          )
        end

        # Visit a ClassDeclaration node.
        def visit_class(node)
          operator =
            if node.superclass
              srange_find_between(node.constant, node.superclass, "<")
            end

          s(
            :class,
            [
              visit(node.constant),
              visit(node.superclass),
              visit(node.bodystmt)
            ],
            smap_definition(
              srange_length(node.start_char, 5),
              operator,
              srange_node(node.constant),
              srange_length(node.end_char, -3)
            ).with_expression(srange_node(node))
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

            begin_token = srange_length(node.arguments.start_char, 1)
            end_token = srange_length(node.arguments.end_char, -1)
          end

          dot_bound =
            if node.arguments
              node.arguments.start_char
            elsif node.block
              node.block.start_char
            else
              node.end_char
            end

          expression =
            if node.arguments.is_a?(ArgParen)
              srange(node.start_char, node.arguments.end_char)
            elsif node.arguments.is_a?(Args) && node.arguments.parts.any?
              last_part = node.arguments.parts.last
              end_char =
                if last_part.is_a?(Heredoc)
                  last_part.beginning.end_char
                else
                  last_part.end_char
                end

              srange(node.start_char, end_char)
            elsif node.block
              if node.receiver
                srange(node.receiver.start_char, node.message.end_char)
              else
                srange_node(node.message)
              end
            else
              srange_node(node)
            end

          call =
            s(
              if node.operator.is_a?(Op) && node.operator.value == "&."
                :csend
              else
                :send
              end,
              children,
              smap_send(
                if node.operator == :"::"
                  srange_find(
                    node.receiver.end_char,
                    if node.message == :call
                      dot_bound
                    else
                      node.message.start_char
                    end,
                    "::"
                  )
                elsif node.operator
                  srange_node(node.operator)
                end,
                node.message == :call ? nil : srange_node(node.message),
                begin_token,
                end_token,
                expression
              )
            )

          if node.block
            type, arguments = block_children(node.block)

            s(
              type,
              [call, arguments, visit(node.block.bodystmt)],
              smap_collection(
                srange_node(node.block.opening),
                srange_length(
                  node.end_char,
                  node.block.opening.is_a?(Kw) ? -3 : -1
                ),
                srange_node(node)
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
            smap_constant(nil, srange_node(node), srange_node(node))
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
              smap_constant(
                srange_find_between(node.parent, node.constant, "::"),
                srange_node(node.constant),
                srange_node(node)
              )
            )
          end
        end

        # Visit a ConstPathRef node.
        def visit_const_path_ref(node)
          s(
            :const,
            [visit(node.parent), node.constant.value.to_sym],
            smap_constant(
              srange_find_between(node.parent, node.constant, "::"),
              srange_node(node.constant),
              srange_node(node)
            )
          )
        end

        # Visit a ConstRef node.
        def visit_const_ref(node)
          s(
            :const,
            [nil, node.constant.value.to_sym],
            smap_constant(nil, srange_node(node.constant), srange_node(node))
          )
        end

        # Visit a CVar node.
        def visit_cvar(node)
          s(
            :cvar,
            [node.value.to_sym],
            smap_variable(srange_node(node), srange_node(node))
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
                smap_collection_bare(child.location&.expression)
              )
            when Paren
              child = visit(node.params.contents)

              s(
                child.type,
                child.children,
                smap_collection(
                  srange_length(node.params.start_char, 1),
                  srange_length(node.params.end_char, -1),
                  srange_node(node.params)
                )
              )
            else
              s(:args, [], smap_collection_bare(nil))
            end

          location =
            if node.endless?
              smap_method_definition(
                srange_length(node.start_char, 3),
                nil,
                srange_node(node.name),
                nil,
                srange_find_between(
                  (node.params || node.name),
                  node.bodystmt,
                  "="
                ),
                srange_node(node)
              )
            else
              smap_method_definition(
                srange_length(node.start_char, 3),
                nil,
                srange_node(node.name),
                srange_length(node.end_char, -3),
                nil,
                srange_node(node)
              )
            end

          if node.target
            target =
              node.target.is_a?(Paren) ? node.target.contents : node.target

            s(
              :defs,
              [visit(target), name, args, visit(node.bodystmt)],
              smap_method_definition(
                location.keyword,
                srange_node(node.operator),
                location.name,
                location.end,
                location.assignment,
                location.expression
              )
            )
          else
            s(:def, [name, args, visit(node.bodystmt)], location)
          end
        end

        # Visit a Defined node.
        def visit_defined(node)
          paren_range = (node.start_char + 8)...node.end_char
          begin_token, end_token =
            if buffer.source[paren_range].include?("(")
              [
                srange_find(paren_range.begin, paren_range.end, "("),
                srange_length(node.end_char, -1)
              ]
            end

          s(
            :defined?,
            [visit(node.value)],
            smap_keyword(
              srange_length(node.start_char, 8),
              begin_token,
              end_token,
              srange_node(node)
            )
          )
        end

        # Visit a DynaSymbol node.
        def visit_dyna_symbol(node)
          location =
            if node.quote
              smap_collection(
                srange_length(node.start_char, node.quote.length),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
            else
              smap_collection_bare(srange_node(node))
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
          begin_start = node.predicate.end_char
          begin_end =
            if node.statements.empty?
              node.statements.end_char
            else
              node.statements.body.first.start_char
            end

          begin_token =
            if buffer.source[begin_start...begin_end].include?("then")
              srange_find(begin_start, begin_end, "then")
            elsif buffer.source[begin_start...begin_end].include?(";")
              srange_find(begin_start, begin_end, ";")
            end

          else_token =
            case node.consequent
            when Elsif
              srange_length(node.consequent.start_char, 5)
            when Else
              srange_length(node.consequent.start_char, 4)
            end

          expression = srange(node.start_char, node.statements.end_char - 1)

          s(
            :if,
            [
              visit(node.predicate),
              visit(node.statements),
              visit(node.consequent)
            ],
            smap_condition(
              srange_length(node.start_char, 5),
              begin_token,
              else_token,
              nil,
              expression
            )
          )
        end

        # Visit an ENDBlock node.
        def visit_END(node)
          s(
            :postexe,
            [visit(node.statements)],
            smap_keyword(
              srange_length(node.start_char, 3),
              srange_find(node.start_char + 3, node.statements.start_char, "{"),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit an Ensure node.
        def visit_ensure(node)
          start_char = node.start_char
          end_char =
            if node.statements.empty?
              start_char + 6
            else
              node.statements.body.last.end_char
            end

          s(
            :ensure,
            [visit(node.statements)],
            smap_condition(
              srange_length(start_char, 6),
              nil,
              nil,
              nil,
              srange(start_char, end_char)
            )
          )
        end

        # Visit a Field node.
        def visit_field(node)
          message =
            case stack[-2]
            when Assign, MLHS
              Ident.new(
                value: "#{node.name.value}=",
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
            if %w[+ -].include?(buffer.source[node.start_char])
              srange_length(node.start_char, 1)
            end

          s(
            :float,
            [node.value.to_f],
            smap_operator(operator, srange_node(node))
          )
        end

        # Visit a FndPtn node.
        def visit_fndptn(node)
          left, right =
            [node.left, node.right].map do |child|
              location =
                smap_operator(
                  srange_length(child.start_char, 1),
                  srange_node(child)
                )

              if child.is_a?(VarField) && child.value.nil?
                s(:match_rest, [], location)
              else
                s(:match_rest, [visit(child)], location)
              end
            end

          inner =
            s(
              :find_pattern,
              [left, *visit_all(node.values), right],
              smap_collection(
                srange_length(node.start_char, 1),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
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
            smap_for(
              srange_length(node.start_char, 3),
              srange_find_between(node.index, node.collection, "in"),
              srange_search_between(node.collection, node.statements, "do") ||
                srange_search_between(node.collection, node.statements, ";"),
              srange_length(node.end_char, -3),
              srange_node(node)
            )
          )
        end

        # Visit a GVar node.
        def visit_gvar(node)
          s(
            :gvar,
            [node.value.to_sym],
            smap_variable(srange_node(node), srange_node(node))
          )
        end

        # Visit a HashLiteral node.
        def visit_hash(node)
          s(
            :hash,
            visit_all(node.assocs),
            smap_collection(
              srange_length(node.start_char, 1),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit a Heredoc node.
        def visit_heredoc(node)
          heredoc = HeredocBuilder.new(node)

          # For each part of the heredoc, if it's a string content node, split
          # it into multiple string content nodes, one for each line. Otherwise,
          # visit the node as normal.
          node.parts.each do |part|
            if part.is_a?(TStringContent) && part.value.count("\n") > 1
              index = part.start_char
              lines = part.value.split("\n")

              lines.each do |line|
                length = line.length + 1
                location = smap_collection_bare(srange_length(index, length))

                heredoc << s(:str, ["#{line}\n"], location)
                index += length
              end
            else
              heredoc << visit(part)
            end
          end

          # Now that we have all of the pieces on the heredoc, we can trim it if
          # it is a heredoc that supports trimming (i.e., it has a ~ on the
          # declaration).
          heredoc.trim!

          # Generate the location for the heredoc, which goes from the
          # declaration to the ending delimiter.
          location =
            smap_heredoc(
              srange_node(node.beginning),
              srange(
                if node.parts.empty?
                  node.beginning.end_char + 1
                else
                  node.parts.first.start_char
                end,
                node.ending.start_char
              ),
              srange(node.ending.start_char, node.ending.end_char - 1)
            )

          # Finally, decide which kind of heredoc node to generate based on its
          # declaration and contents.
          if node.beginning.value.match?(/`\w+`\z/)
            s(:xstr, heredoc.segments, location)
          elsif heredoc.segments.length == 1
            segment = heredoc.segments.first
            s(segment.type, segment.children, location)
          else
            s(:dstr, heredoc.segments, location)
          end
        end

        # Visit a HshPtn node.
        def visit_hshptn(node)
          children =
            node.keywords.map do |(keyword, value)|
              next s(:pair, [visit(keyword), visit(value)], nil) if value

              case keyword
              when DynaSymbol
                raise if keyword.parts.length > 1
                s(:match_var, [keyword.parts.first.value.to_sym], nil)
              when Label
                s(:match_var, [keyword.value.chomp(":").to_sym], nil)
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
            smap_variable(srange_node(node), srange_node(node))
          )
        end

        # Visit an IfNode node.
        def visit_if(node)
          s(
            :if,
            [
              visit_predicate(node.predicate),
              visit(node.statements),
              visit(node.consequent)
            ],
            if node.modifier?
              smap_keyword_bare(
                srange_find_between(node.statements, node.predicate, "if"),
                srange_node(node)
              )
            else
              begin_start = node.predicate.end_char
              begin_end =
                if node.statements.empty?
                  node.statements.end_char
                else
                  node.statements.body.first.start_char
                end

              begin_token =
                if buffer.source[begin_start...begin_end].include?("then")
                  srange_find(begin_start, begin_end, "then")
                elsif buffer.source[begin_start...begin_end].include?(";")
                  srange_find(begin_start, begin_end, ";")
                end

              else_token =
                case node.consequent
                when Elsif
                  srange_length(node.consequent.start_char, 5)
                when Else
                  srange_length(node.consequent.start_char, 4)
                end

              smap_condition(
                srange_length(node.start_char, 2),
                begin_token,
                else_token,
                srange_length(node.end_char, -3),
                srange_node(node)
              )
            end
          )
        end

        # Visit an IfOp node.
        def visit_if_op(node)
          s(
            :if,
            [visit(node.predicate), visit(node.truthy), visit(node.falsy)],
            smap_ternary(
              srange_find_between(node.predicate, node.truthy, "?"),
              srange_find_between(node.truthy, node.falsy, ":"),
              srange_node(node)
            )
          )
        end

        # Visit an Imaginary node.
        def visit_imaginary(node)
          s(
            :complex,
            [
              # We have to do an eval here in order to get the value in case
              # it's something like 42ri. to_c will not give the right value in
              # that case. Maybe there's an API for this but I can't find it.
              eval(node.value)
            ],
            smap_operator(nil, srange_node(node))
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
            begin_token =
              srange_search_between(node.pattern, node.statements, "then")

            end_char =
              if begin_token || node.statements.empty?
                node.statements.end_char - 1
              else
                node.statements.body.last.start_char
              end

            s(
              :in_pattern,
              [visit(node.pattern), nil, visit(node.statements)],
              smap_keyword(
                srange_length(node.start_char, 2),
                begin_token,
                nil,
                srange(node.start_char, end_char)
              )
            )
          end
        end

        # Visit an Int node.
        def visit_int(node)
          operator =
            if %w[+ -].include?(buffer.source[node.start_char])
              srange_length(node.start_char, 1)
            end

          s(:int, [node.value.to_i], smap_operator(operator, srange_node(node)))
        end

        # Visit an IVar node.
        def visit_ivar(node)
          s(
            :ivar,
            [node.value.to_sym],
            smap_variable(srange_node(node), srange_node(node))
          )
        end

        # Visit a Kw node.
        def visit_kw(node)
          location = smap(srange_node(node))

          case node.value
          when "__FILE__"
            s(:str, [buffer.name], location)
          when "__LINE__"
            s(
              :int,
              [node.location.start_line + buffer.first_line - 1],
              location
            )
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
            s(:kwrestarg, [], smap_variable(nil, srange_node(node)))
          else
            s(
              :kwrestarg,
              [node.name.value.to_sym],
              smap_variable(srange_node(node.name), srange_node(node))
            )
          end
        end

        # Visit a Label node.
        def visit_label(node)
          s(
            :sym,
            [node.value.chomp(":").to_sym],
            smap_collection_bare(srange(node.start_char, node.end_char - 1))
          )
        end

        # Visit a Lambda node.
        def visit_lambda(node)
          args =
            node.params.is_a?(LambdaVar) ? node.params : node.params.contents
          args_node = visit(args)

          type = :block
          if args.empty? && (maximum = num_block_type(node.statements))
            type = :numblock
            args_node = maximum
          end

          begin_token, end_token =
            if (
                 srange =
                   srange_search_between(node.params, node.statements, "{")
               )
              [srange, srange_length(node.end_char, -1)]
            else
              [
                srange_find_between(node.params, node.statements, "do"),
                srange_length(node.end_char, -3)
              ]
            end

          selector = srange_length(node.start_char, 2)

          s(
            type,
            [
              if ::Parser::Builders::Default.emit_lambda
                s(:lambda, [], smap(selector))
              else
                s(:send, [nil, :lambda], smap_send_bare(selector, selector))
              end,
              args_node,
              visit(node.statements)
            ],
            smap_collection(begin_token, end_token, srange_node(node))
          )
        end

        # Visit a LambdaVar node.
        def visit_lambda_var(node)
          shadowargs =
            node.locals.map do |local|
              s(
                :shadowarg,
                [local.value.to_sym],
                smap_variable(srange_node(local), srange_node(local))
              )
            end

          location =
            if node.start_char == node.end_char
              smap_collection_bare(nil)
            elsif buffer.source[node.start_char - 1] == "("
              smap_collection(
                srange_length(node.start_char, 1),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
            else
              smap_collection_bare(srange_node(node))
            end

          s(:args, visit(node.params).children + shadowargs, location)
        end

        # Visit an MAssign node.
        def visit_massign(node)
          s(
            :masgn,
            [visit(node.target), visit(node.value)],
            smap_operator(
              srange_find_between(node.target, node.value, "="),
              srange_node(node)
            )
          )
        end

        # Visit a MethodAddBlock node.
        def visit_method_add_block(node)
          case node.call
          when ARef, Super, ZSuper
            type, arguments = block_children(node.block)

            s(
              type,
              [visit(node.call), arguments, visit(node.block.bodystmt)],
              smap_collection(
                srange_node(node.block.opening),
                srange_length(
                  node.block.end_char,
                  node.block.keywords? ? -3 : -1
                ),
                srange_node(node)
              )
            )
          else
            visit_command_call(
              CommandCall.new(
                receiver: node.call.receiver,
                operator: node.call.operator,
                message: node.call.message,
                arguments: node.call.arguments,
                block: node.block,
                location: node.location
              )
            )
          end
        end

        # Visit an MLHS node.
        def visit_mlhs(node)
          s(
            :mlhs,
            node.parts.map do |part|
              if part.is_a?(Ident)
                s(
                  :arg,
                  [part.value.to_sym],
                  smap_variable(srange_node(part), srange_node(part))
                )
              else
                visit(part)
              end
            end,
            smap_collection_bare(srange_node(node))
          )
        end

        # Visit an MLHSParen node.
        def visit_mlhs_paren(node)
          child = visit(node.contents)

          s(
            child.type,
            child.children,
            smap_collection(
              srange_length(node.start_char, 1),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit a ModuleDeclaration node.
        def visit_module(node)
          s(
            :module,
            [visit(node.constant), visit(node.bodystmt)],
            smap_definition(
              srange_length(node.start_char, 6),
              nil,
              srange_node(node.constant),
              srange_length(node.end_char, -3)
            ).with_expression(srange_node(node))
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
            smap_keyword_bare(
              srange_length(node.start_char, 4),
              srange_node(node)
            )
          )
        end

        # Visit a Not node.
        def visit_not(node)
          if node.statement.nil?
            begin_token = srange_find(node.start_char, nil, "(")
            end_token = srange_find(node.start_char, nil, ")")

            s(
              :send,
              [
                s(
                  :begin,
                  [],
                  smap_collection(
                    begin_token,
                    end_token,
                    begin_token.join(end_token)
                  )
                ),
                :!
              ],
              smap_send_bare(
                srange_length(node.start_char, 3),
                srange_node(node)
              )
            )
          else
            begin_token, end_token =
              if node.parentheses?
                [
                  srange_find(
                    node.start_char + 3,
                    node.statement.start_char,
                    "("
                  ),
                  srange_length(node.end_char, -1)
                ]
              end

            s(
              :send,
              [visit(node.statement), :!],
              smap_send(
                nil,
                srange_length(node.start_char, 3),
                begin_token,
                end_token,
                srange_node(node)
              )
            )
          end
        end

        # Visit an OpAssign node.
        def visit_opassign(node)
          target = visit(node.target)
          location =
            target
              .location
              .with_expression(srange_node(node))
              .with_operator(srange_node(node.operator))

          case node.operator.value
          when "||="
            s(:or_asgn, [target, visit(node.value)], location)
          when "&&="
            s(:and_asgn, [target, visit(node.value)], location)
          else
            s(
              :op_asgn,
              [
                target,
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
                  smap_variable(srange_node(required), srange_node(required))
                )
              end
            end

          children +=
            node.optionals.map do |(name, value)|
              s(
                :optarg,
                [name.value.to_sym, visit(value)],
                smap_variable(
                  srange_node(name),
                  srange_node(name).join(srange_node(value))
                ).with_operator(srange_find_between(name, value, "="))
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
                smap_variable(srange_node(post), srange_node(post))
              )
            end

          children +=
            node.keywords.map do |(name, value)|
              key = name.value.chomp(":").to_sym

              if value
                s(
                  :kwoptarg,
                  [key, visit(value)],
                  smap_variable(
                    srange(name.start_char, name.end_char - 1),
                    srange_node(name).join(srange_node(value))
                  )
                )
              else
                s(
                  :kwarg,
                  [key],
                  smap_variable(
                    srange(name.start_char, name.end_char - 1),
                    srange_node(name)
                  )
                )
              end
            end

          case node.keyword_rest
          when nil, ArgsForward
            # do nothing
          when :nil
            children << s(
              :kwnilarg,
              [],
              smap_variable(srange_length(node.end_char, -3), srange_node(node))
            )
          else
            children << visit(node.keyword_rest)
          end

          children << visit(node.block) if node.block

          if node.keyword_rest.is_a?(ArgsForward)
            location = smap(srange_node(node.keyword_rest))

            # If there are no other arguments and we have the emit_forward_arg
            # option enabled, then the entire argument list is represented by a
            # single forward_args node.
            if children.empty? && !::Parser::Builders::Default.emit_forward_arg
              return s(:forward_args, [], location)
            end

            # Otherwise, we need to insert a forward_arg node into the list of
            # parameters before any keyword rest or block parameters.
            index =
              node.requireds.length + node.optionals.length +
                node.keywords.length
            children.insert(index, s(:forward_arg, [], location))
          end

          location =
            unless children.empty?
              first = children.first.location.expression
              last = children.last.location.expression
              smap_collection_bare(first.join(last))
            end

          s(:args, children, location)
        end

        # Visit a Paren node.
        def visit_paren(node)
          location =
            smap_collection(
              srange_length(node.start_char, 1),
              srange_length(node.end_char, -1),
              srange_node(node)
            )

          if node.contents.nil? ||
               (node.contents.is_a?(Statements) && node.contents.empty?)
            s(:begin, [], location)
          else
            child = visit(node.contents)
            child.type == :begin ? child : s(:begin, [child], location)
          end
        end

        # Visit a PinnedBegin node.
        def visit_pinned_begin(node)
          s(
            :pin,
            [
              s(
                :begin,
                [visit(node.statement)],
                smap_collection(
                  srange_length(node.start_char + 1, 1),
                  srange_length(node.end_char, -1),
                  srange(node.start_char + 1, node.end_char)
                )
              )
            ],
            smap_send_bare(srange_length(node.start_char, 1), srange_node(node))
          )
        end

        # Visit a PinnedVarRef node.
        def visit_pinned_var_ref(node)
          s(
            :pin,
            [visit(node.value)],
            smap_send_bare(srange_length(node.start_char, 1), srange_node(node))
          )
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
            smap_operator(srange_node(node.operator), srange_node(node))
          )
        end

        # Visit an RAssign node.
        def visit_rassign(node)
          s(
            node.operator.value == "=>" ? :match_pattern : :match_pattern_p,
            [visit(node.value), visit(node.pattern)],
            smap_operator(srange_node(node.operator), srange_node(node))
          )
        end

        # Visit a Rational node.
        def visit_rational(node)
          s(:rational, [node.value.to_r], smap_operator(nil, srange_node(node)))
        end

        # Visit a Redo node.
        def visit_redo(node)
          s(:redo, [], smap_keyword_bare(srange_node(node), srange_node(node)))
        end

        # Visit a RegexpLiteral node.
        def visit_regexp_literal(node)
          s(
            :regexp,
            visit_all(node.parts).push(
              s(
                :regopt,
                node.ending.scan(/[a-z]/).sort.map(&:to_sym),
                smap(srange_length(node.end_char, -(node.ending.length - 1)))
              )
            ),
            smap_collection(
              srange_length(node.start_char, node.beginning.length),
              srange_length(node.end_char - node.ending.length, 1),
              srange_node(node)
            )
          )
        end

        # Visit a Rescue node.
        def visit_rescue(node)
          # In the parser gem, there is a separation between the rescue node and
          # the rescue body. They have different bounds, so we have to calculate
          # those here.
          start_char = node.start_char

          body_end_char =
            if node.statements.empty?
              start_char + 6
            else
              node.statements.body.last.end_char
            end

          end_char =
            if node.consequent
              end_node = node.consequent
              end_node = end_node.consequent while end_node.consequent

              if end_node.statements.empty?
                start_char + 6
              else
                end_node.statements.body.last.end_char
              end
            else
              body_end_char
            end

          # These locations are reused for multiple children.
          keyword = srange_length(start_char, 6)
          body_expression = srange(start_char, body_end_char)
          expression = srange(start_char, end_char)

          exceptions =
            case node.exception&.exceptions
            when nil
              nil
            when MRHS
              visit_array(
                ArrayLiteral.new(
                  lbracket: nil,
                  contents:
                    Args.new(
                      parts: node.exception.exceptions.parts,
                      location: node.exception.exceptions.location
                    ),
                  location: node.exception.exceptions.location
                )
              )
            else
              visit_array(
                ArrayLiteral.new(
                  lbracket: nil,
                  contents:
                    Args.new(
                      parts: [node.exception.exceptions],
                      location: node.exception.exceptions.location
                    ),
                  location: node.exception.exceptions.location
                )
              )
            end

          resbody =
            if node.exception.nil?
              s(
                :resbody,
                [nil, nil, visit(node.statements)],
                smap_rescue_body(keyword, nil, nil, body_expression)
              )
            elsif node.exception.variable.nil?
              s(
                :resbody,
                [exceptions, nil, visit(node.statements)],
                smap_rescue_body(keyword, nil, nil, body_expression)
              )
            else
              s(
                :resbody,
                [
                  exceptions,
                  visit(node.exception.variable),
                  visit(node.statements)
                ],
                smap_rescue_body(
                  keyword,
                  srange_find(
                    node.start_char + 6,
                    node.exception.variable.start_char,
                    "=>"
                  ),
                  nil,
                  body_expression
                )
              )
            end

          children = [resbody]
          if node.consequent
            children += visit(node.consequent).children
          else
            children << nil
          end

          s(:rescue, children, smap_condition_bare(expression))
        end

        # Visit a RescueMod node.
        def visit_rescue_mod(node)
          keyword = srange_find_between(node.statement, node.value, "rescue")

          s(
            :rescue,
            [
              visit(node.statement),
              s(
                :resbody,
                [nil, nil, visit(node.value)],
                smap_rescue_body(
                  keyword,
                  nil,
                  nil,
                  keyword.join(srange_node(node.value))
                )
              ),
              nil
            ],
            smap_condition_bare(srange_node(node))
          )
        end

        # Visit a RestParam node.
        def visit_rest_param(node)
          if node.name
            s(
              :restarg,
              [node.name.value.to_sym],
              smap_variable(srange_node(node.name), srange_node(node))
            )
          else
            s(:restarg, [], smap_variable(nil, srange_node(node)))
          end
        end

        # Visit a Retry node.
        def visit_retry(node)
          s(:retry, [], smap_keyword_bare(srange_node(node), srange_node(node)))
        end

        # Visit a ReturnNode node.
        def visit_return(node)
          s(
            :return,
            node.arguments ? visit_all(node.arguments.parts) : [],
            smap_keyword_bare(
              srange_length(node.start_char, 6),
              srange_node(node)
            )
          )
        end

        # Visit an SClass node.
        def visit_sclass(node)
          s(
            :sclass,
            [visit(node.target), visit(node.bodystmt)],
            smap_definition(
              srange_length(node.start_char, 5),
              srange_find(node.start_char + 5, node.target.start_char, "<<"),
              nil,
              srange_length(node.end_char, -3)
            ).with_expression(srange_node(node))
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
              smap_collection_bare(
                srange(children.first.start_char, children.last.end_char)
              )
            )
          end
        end

        # Visit a StringConcat node.
        def visit_string_concat(node)
          s(
            :dstr,
            [visit(node.left), visit(node.right)],
            smap_collection_bare(srange_node(node))
          )
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
            smap_collection(
              srange_length(node.start_char, 2),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        # Visit a StringLiteral node.
        def visit_string_literal(node)
          location =
            if node.quote
              smap_collection(
                srange_length(node.start_char, node.quote.length),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
            else
              smap_collection_bare(srange_node(node))
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
              smap_keyword_bare(
                srange_length(node.start_char, 5),
                srange_node(node)
              )
            )
          else
            case node.arguments.arguments
            when nil
              s(
                :super,
                [],
                smap_keyword(
                  srange_length(node.start_char, 5),
                  srange_find(node.start_char + 5, node.end_char, "("),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            when ArgsForward
              s(
                :super,
                [visit(node.arguments.arguments)],
                smap_keyword(
                  srange_length(node.start_char, 5),
                  srange_find(node.start_char + 5, node.end_char, "("),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            else
              s(
                :super,
                visit_all(node.arguments.arguments.parts),
                smap_keyword(
                  srange_length(node.start_char, 5),
                  srange_find(node.start_char + 5, node.end_char, "("),
                  srange_length(node.end_char, -1),
                  srange_node(node)
                )
              )
            end
          end
        end

        # Visit a SymbolLiteral node.
        def visit_symbol_literal(node)
          begin_token =
            if buffer.source[node.start_char] == ":"
              srange_length(node.start_char, 1)
            end

          s(
            :sym,
            [node.value.value.to_sym],
            smap_collection(begin_token, nil, srange_node(node))
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
              s(:cbase, [], smap(srange_length(node.start_char, 2))),
              node.constant.value.to_sym
            ],
            smap_constant(
              srange_length(node.start_char, 2),
              srange_node(node.constant),
              srange_node(node)
            )
          )
        end

        # Visit a TopConstRef node.
        def visit_top_const_ref(node)
          s(
            :const,
            [
              s(:cbase, [], smap(srange_length(node.start_char, 2))),
              node.constant.value.to_sym
            ],
            smap_constant(
              srange_length(node.start_char, 2),
              srange_node(node.constant),
              srange_node(node)
            )
          )
        end

        # Visit a TStringContent node.
        def visit_tstring_content(node)
          dumped = node.value.gsub(/([^[:ascii:]])/) { $1.dump[1...-1] }

          s(
            :str,
            ["\"#{dumped}\"".undump],
            smap_collection_bare(srange_node(node))
          )
        end

        # Visit a Unary node.
        def visit_unary(node)
          # Special handling here for flipflops
          if (paren = node.statement).is_a?(Paren) &&
               paren.contents.is_a?(Statements) &&
               paren.contents.body.length == 1 &&
               (range = paren.contents.body.first).is_a?(RangeNode) &&
               node.operator == "!"
            s(
              :send,
              [
                s(
                  :begin,
                  [
                    s(
                      range.operator.value == ".." ? :iflipflop : :eflipflop,
                      visit(range).children,
                      smap_operator(
                        srange_node(range.operator),
                        srange_node(range)
                      )
                    )
                  ],
                  smap_collection(
                    srange_length(paren.start_char, 1),
                    srange_length(paren.end_char, -1),
                    srange_node(paren)
                  )
                ),
                :!
              ],
              smap_send_bare(
                srange_length(node.start_char, 1),
                srange_node(node)
              )
            )
          elsif node.operator == "!" && node.statement.is_a?(RegexpLiteral)
            s(
              :send,
              [
                s(
                  :match_current_line,
                  [visit(node.statement)],
                  smap(srange_node(node.statement))
                ),
                :!
              ],
              smap_send_bare(
                srange_length(node.start_char, 1),
                srange_node(node)
              )
            )
          else
            visit(canonical_unary(node))
          end
        end

        # Visit an Undef node.
        def visit_undef(node)
          s(
            :undef,
            visit_all(node.symbols),
            smap_keyword_bare(
              srange_length(node.start_char, 5),
              srange_node(node)
            )
          )
        end

        # Visit an UnlessNode node.
        def visit_unless(node)
          s(
            :if,
            [
              visit_predicate(node.predicate),
              visit(node.consequent),
              visit(node.statements)
            ],
            if node.modifier?
              smap_keyword_bare(
                srange_find_between(node.statements, node.predicate, "unless"),
                srange_node(node)
              )
            else
              begin_start = node.predicate.end_char
              begin_end =
                if node.statements.empty?
                  node.statements.end_char
                else
                  node.statements.body.first.start_char
                end

              begin_token =
                if buffer.source[begin_start...begin_end].include?("then")
                  srange_find(begin_start, begin_end, "then")
                elsif buffer.source[begin_start...begin_end].include?(";")
                  srange_find(begin_start, begin_end, ";")
                end

              else_token =
                if node.consequent
                  srange_length(node.consequent.start_char, 4)
                end

              smap_condition(
                srange_length(node.start_char, 6),
                begin_token,
                else_token,
                srange_length(node.end_char, -3),
                srange_node(node)
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
              smap_keyword_bare(
                srange_find_between(node.statements, node.predicate, "until"),
                srange_node(node)
              )
            else
              smap_keyword(
                srange_length(node.start_char, 5),
                srange_search_between(node.predicate, node.statements, "do") ||
                  srange_search_between(node.predicate, node.statements, ";"),
                srange_length(node.end_char, -3),
                srange_node(node)
              )
            end
          )
        end

        # Visit a VarField node.
        def visit_var_field(node)
          name = node.value.value.to_sym
          match_var =
            [stack[-3], stack[-2]].any? do |parent|
              case parent
              when AryPtn, FndPtn, HshPtn, In, RAssign
                true
              when Binary
                parent.operator == :"=>"
              else
                false
              end
            end

          if match_var
            s(
              :match_var,
              [name],
              smap_variable(srange_node(node.value), srange_node(node.value))
            )
          elsif node.value.is_a?(Const)
            s(
              :casgn,
              [nil, name],
              smap_constant(nil, srange_node(node.value), srange_node(node))
            )
          else
            location = smap_variable(srange_node(node), srange_node(node))

            case node.value
            when CVar
              s(:cvasgn, [name], location)
            when GVar
              s(:gvasgn, [name], location)
            when Ident
              s(:lvasgn, [name], location)
            when IVar
              s(:ivasgn, [name], location)
            when VarRef
              s(:lvasgn, [name], location)
            else
              s(:match_rest, [], nil)
            end
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
          keyword = srange_length(node.start_char, 4)
          begin_token =
            if buffer.source[node.statements.start_char] == ";"
              srange_length(node.statements.start_char, 1)
            end

          end_char =
            if node.statements.body.empty?
              node.statements.end_char
            else
              node.statements.body.last.end_char
            end

          s(
            :when,
            visit_all(node.arguments.parts) + [visit(node.statements)],
            smap_keyword(
              keyword,
              begin_token,
              nil,
              srange(keyword.begin_pos, end_char)
            )
          )
        end

        # Visit a WhileNode node.
        def visit_while(node)
          s(
            loop_post?(node) ? :while_post : :while,
            [visit(node.predicate), visit(node.statements)],
            if node.modifier?
              smap_keyword_bare(
                srange_find_between(node.statements, node.predicate, "while"),
                srange_node(node)
              )
            else
              smap_keyword(
                srange_length(node.start_char, 5),
                srange_search_between(node.predicate, node.statements, "do") ||
                  srange_search_between(node.predicate, node.statements, ";"),
                srange_length(node.end_char, -3),
                srange_node(node)
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
            smap_collection(
              srange_length(
                node.start_char,
                buffer.source[node.start_char] == "%" ? 3 : 1
              ),
              srange_length(node.end_char, -1),
              srange_node(node)
            )
          )
        end

        def visit_yield(node)
          case node.arguments
          when nil
            s(
              :yield,
              [],
              smap_keyword_bare(
                srange_length(node.start_char, 5),
                srange_node(node)
              )
            )
          when Args
            s(
              :yield,
              visit_all(node.arguments.parts),
              smap_keyword_bare(
                srange_length(node.start_char, 5),
                srange_node(node)
              )
            )
          else
            s(
              :yield,
              visit_all(node.arguments.contents.parts),
              smap_keyword(
                srange_length(node.start_char, 5),
                srange_length(node.arguments.start_char, 1),
                srange_length(node.end_char, -1),
                srange_node(node)
              )
            )
          end
        end

        # Visit a ZSuper node.
        def visit_zsuper(node)
          s(
            :zsuper,
            [],
            smap_keyword_bare(
              srange_length(node.start_char, 5),
              srange_node(node)
            )
          )
        end
      end

      private

      def block_children(node)
        arguments =
          if node.block_var
            visit(node.block_var)
          else
            s(:args, [], smap_collection_bare(nil))
          end

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
                  start_char: node.start_char,
                  start_column: node.location.start_column,
                  end_line: node.location.start_line,
                  end_char: node.start_char + length,
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

        start_char = node.left.end_char
        end_char = node.right.start_char

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
      def smap(expression)
        ::Parser::Source::Map.new(expression)
      end

      # Constructs a new source map for a collection.
      def smap_collection(begin_token, end_token, expression)
        ::Parser::Source::Map::Collection.new(
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a collection without a begin or end.
      def smap_collection_bare(expression)
        smap_collection(nil, nil, expression)
      end

      # Constructs a new source map for a conditional expression.
      def smap_condition(
        keyword,
        begin_token,
        else_token,
        end_token,
        expression
      )
        ::Parser::Source::Map::Condition.new(
          keyword,
          begin_token,
          else_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a conditional expression with no begin
      # or end.
      def smap_condition_bare(expression)
        smap_condition(nil, nil, nil, nil, expression)
      end

      # Constructs a new source map for a constant reference.
      def smap_constant(double_colon, name, expression)
        ::Parser::Source::Map::Constant.new(double_colon, name, expression)
      end

      # Constructs a new source map for a class definition.
      def smap_definition(keyword, operator, name, end_token)
        ::Parser::Source::Map::Definition.new(
          keyword,
          operator,
          name,
          end_token
        )
      end

      # Constructs a new source map for a for loop.
      def smap_for(keyword, in_token, begin_token, end_token, expression)
        ::Parser::Source::Map::For.new(
          keyword,
          in_token,
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a heredoc.
      def smap_heredoc(expression, heredoc_body, heredoc_end)
        ::Parser::Source::Map::Heredoc.new(
          expression,
          heredoc_body,
          heredoc_end
        )
      end

      # Construct a source map for an index operation.
      def smap_index(begin_token, end_token, expression)
        ::Parser::Source::Map::Index.new(begin_token, end_token, expression)
      end

      # Constructs a new source map for the use of a keyword.
      def smap_keyword(keyword, begin_token, end_token, expression)
        ::Parser::Source::Map::Keyword.new(
          keyword,
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for the use of a keyword without a begin or
      # end token.
      def smap_keyword_bare(keyword, expression)
        smap_keyword(keyword, nil, nil, expression)
      end

      # Constructs a new source map for a method definition.
      def smap_method_definition(
        keyword,
        operator,
        name,
        end_token,
        assignment,
        expression
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
      def smap_operator(operator, expression)
        ::Parser::Source::Map::Operator.new(operator, expression)
      end

      # Constructs a source map for the body of a rescue clause.
      def smap_rescue_body(keyword, assoc, begin_token, expression)
        ::Parser::Source::Map::RescueBody.new(
          keyword,
          assoc,
          begin_token,
          expression
        )
      end

      # Constructs a new source map for a method call.
      def smap_send(dot, selector, begin_token, end_token, expression)
        ::Parser::Source::Map::Send.new(
          dot,
          selector,
          begin_token,
          end_token,
          expression
        )
      end

      # Constructs a new source map for a method call without a begin or end.
      def smap_send_bare(selector, expression)
        smap_send(nil, selector, nil, nil, expression)
      end

      # Constructs a new source map for a ternary expression.
      def smap_ternary(question, colon, expression)
        ::Parser::Source::Map::Ternary.new(question, colon, expression)
      end

      # Constructs a new source map for a variable.
      def smap_variable(name, expression)
        ::Parser::Source::Map::Variable.new(name, expression)
      end

      # Constructs a new source range from the given start and end offsets.
      def srange(start_char, end_char)
        ::Parser::Source::Range.new(buffer, start_char, end_char)
      end

      # Constructs a new source range by finding the given needle in the given
      # range of the source. If the needle is not found, returns nil.
      def srange_search(start_char, end_char, needle)
        index = buffer.source[start_char...end_char].index(needle)
        return unless index

        offset = start_char + index
        srange(offset, offset + needle.length)
      end

      # Constructs a new source range by searching for the given needle between
      # the end location of the start node and the start location of the end
      # node. If the needle is not found, returns nil.
      def srange_search_between(start_node, end_node, needle)
        srange_search(start_node.end_char, end_node.start_char, needle)
      end

      # Constructs a new source range by finding the given needle in the given
      # range of the source. If it needle is not found, raises an error.
      def srange_find(start_char, end_char, needle)
        srange = srange_search(start_char, end_char, needle)

        unless srange
          slice = buffer.source[start_char...end_char].inspect
          raise "Could not find #{needle.inspect} in #{slice}"
        end

        srange
      end

      # Constructs a new source range by finding the given needle between the
      # end location of the start node and the start location of the end node.
      # If the needle is not found, returns raises an error.
      def srange_find_between(start_node, end_node, needle)
        srange_find(start_node.end_char, end_node.start_char, needle)
      end

      # Constructs a new source range from the given start offset and length.
      def srange_length(start_char, length)
        if length > 0
          srange(start_char, start_char + length)
        else
          srange(start_char + length, start_char)
        end
      end

      # Constructs a new source range using the given node's location.
      def srange_node(node)
        location = node.location
        srange(location.start_char, location.end_char)
      end

      def visit_predicate(node)
        case node
        when RangeNode
          s(
            node.operator.value == ".." ? :iflipflop : :eflipflop,
            visit(node).children,
            smap_operator(srange_node(node.operator), srange_node(node))
          )
        when RegexpLiteral
          s(:match_current_line, [visit(node)], smap(srange_node(node)))
        when Unary
          if node.operator.value == "!" && node.statement.is_a?(RegexpLiteral)
            s(
              :send,
              [s(:match_current_line, [visit(node.statement)]), :!],
              smap_send_bare(srange_node(node.operator), srange_node(node))
            )
          else
            visit(node)
          end
        else
          visit(node)
        end
      end
    end
  end
end
