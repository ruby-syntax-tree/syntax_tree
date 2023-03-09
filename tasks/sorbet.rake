# frozen_string_literal: true

module SyntaxTree
  class RBI
    include DSL

    attr_reader :body, :line

    def initialize
      @body = []
      @line = 1
    end

    def generate
      require "syntax_tree/reflection"

      body << Comment("# typed: strict", false, location)
      @line += 2

      generate_parent
      Reflection.nodes.sort.each { |(_, node)| generate_node(node) }

      body << ClassDeclaration(
        ConstPathRef(VarRef(Const("SyntaxTree")), Const("BasicVisitor")),
        nil,
        BodyStmt(
          Statements(generate_visitor("overridable")),
          nil,
          nil,
          nil,
          nil
        ),
        location
      )

      body << ClassDeclaration(
        ConstPathRef(VarRef(Const("SyntaxTree")), Const("Visitor")),
        ConstPathRef(VarRef(Const("SyntaxTree")), Const("BasicVisitor")),
        BodyStmt(Statements(generate_visitor("override")), nil, nil, nil, nil),
        location
      )

      Formatter.format(nil, Program(Statements(body)))
    end

    private

    def generate_comments(comment)
      comment
        .lines(chomp: true)
        .map { |line| Comment("# #{line}", false, location).tap { @line += 1 } }
    end

    def generate_parent
      attribute = Reflection.nodes[:Program].attributes[:location]
      class_location = location

      node_body = generate_comments(attribute.comment)
      node_body << sig_block { sig_returns { sig_type_for(attribute.type) } }
      @line += 1

      node_body << Command(
        Ident("attr_reader"),
        Args([SymbolLiteral(Ident("location"))]),
        nil,
        location
      )
      @line += 1

      body << ClassDeclaration(
        ConstPathRef(VarRef(Const("SyntaxTree")), Const("Node")),
        nil,
        BodyStmt(Statements(node_body), nil, nil, nil, nil),
        class_location
      )
      @line += 2
    end

    def generate_node(node)
      body.concat(generate_comments(node.comment))
      class_location = location
      @line += 2

      body << ClassDeclaration(
        ConstPathRef(VarRef(Const("SyntaxTree")), Const(node.name.to_s)),
        ConstPathRef(VarRef(Const("SyntaxTree")), Const("Node")),
        BodyStmt(Statements(generate_node_body(node)), nil, nil, nil, nil),
        class_location
      )

      @line += 2
    end

    def generate_node_body(node)
      node_body = []
      node.attributes.sort.each do |(name, attribute)|
        next if name == :location

        node_body.concat(generate_comments(attribute.comment))
        node_body << sig_block { sig_returns { sig_type_for(attribute.type) } }
        @line += 1

        node_body << Command(
          Ident("attr_reader"),
          Args([SymbolLiteral(Ident(attribute.name.to_s))]),
          nil,
          location
        )
        @line += 2
      end

      node_body.concat(generate_initialize(node))

      node_body << sig_block do
        CallNode(
          sig_params do
            BareAssocHash(
              [Assoc(Label("visitor:"), sig_type_for(BasicVisitor))]
            )
          end,
          Period("."),
          Ident("returns"),
          ArgParen(
            Args(
              [CallNode(VarRef(Const("T")), Period("."), Ident("untyped"), nil)]
            )
          )
        )
      end
      @line += 1

      node_body << generate_def_node(
        "accept",
        Paren(
          LParen("("),
          Params.new(requireds: [Ident("visitor")], location: location)
        )
      )
      @line += 2

      node_body << generate_child_nodes
      @line += 1

      node_body << generate_def_node("child_nodes", nil)
      @line += 2

      node_body << sig_block do
        CallNode(
          sig_params do
            BareAssocHash(
              [
                Assoc(
                  Label("other:"),
                  CallNode(
                    VarRef(Const("T")),
                    Period("."),
                    Ident("untyped"),
                    nil
                  )
                )
              ]
            )
          end,
          Period("."),
          sig_returns { ConstPathRef(VarRef(Const("T")), Const("Boolean")) },
          nil
        )
      end
      @line += 1

      node_body << generate_def_node(
        "==",
        Paren(
          LParen("("),
          Params.new(location: location, requireds: [Ident("other")])
        )
      )
      @line += 2

      node_body
    end

    def generate_initialize(node)
      parameters =
        SyntaxTree.const_get(node.name).instance_method(:initialize).parameters

      assocs =
        parameters.map do |(_, name)|
          Assoc(Label("#{name}:"), sig_type_for(node.attributes[name].type))
        end

      node_body = []
      node_body << sig_block do
        CallNode(
          sig_params { BareAssocHash(assocs) },
          Period("."),
          Ident("void"),
          nil
        )
      end
      @line += 1

      params = Params.new(location: location)
      parameters.each do |(type, name)|
        case type
        when :req
          params.requireds << Ident(name.to_s)
        when :keyreq
          params.keywords << [Label("#{name}:"), nil]
        when :key
          params.keywords << [
            Label("#{name}:"),
            CallNode(
              VarRef(Const("T")),
              Period("."),
              Ident("unsafe"),
              ArgParen(Args([VarRef(Kw("nil"))]))
            )
          ]
        else
          raise
        end
      end

      node_body << generate_def_node("initialize", Paren(LParen("("), params))
      @line += 2

      node_body
    end

    def generate_child_nodes
      type =
        Reflection::Type::ArrayType.new(
          Reflection::Type::UnionType.new([NilClass, Node])
        )

      sig_block { sig_returns { sig_type_for(type) } }
    end

    def generate_def_node(name, params)
      DefNode(
        nil,
        nil,
        Ident(name),
        params,
        BodyStmt(Statements([VoidStmt()]), nil, nil, nil, nil),
        location
      )
    end

    def generate_visitor(override)
      body = []

      Reflection.nodes.each do |name, node|
        body << sig_block do
          CallNode(
            CallNode(
              Ident(override),
              Period("."),
              sig_params do
                BareAssocHash(
                  [
                    Assoc(
                      Label("node:"),
                      sig_type_for(SyntaxTree.const_get(name))
                    )
                  ]
                )
              end,
              nil
            ),
            Period("."),
            sig_returns do
              CallNode(VarRef(Const("T")), Period("."), Ident("untyped"), nil)
            end,
            nil
          )
        end

        body << generate_def_node(
          node.visitor_method,
          Paren(
            LParen("("),
            Params.new(requireds: [Ident("node")], location: location)
          )
        )

        @line += 2
      end

      body
    end

    def sig_block
      MethodAddBlock(
        CallNode(nil, nil, Ident("sig"), nil),
        BlockNode(
          LBrace("{"),
          nil,
          BodyStmt(Statements([yield]), nil, nil, nil, nil)
        ),
        location
      )
    end

    def sig_params
      CallNode(nil, nil, Ident("params"), ArgParen(Args([yield])))
    end

    def sig_returns
      CallNode(nil, nil, Ident("returns"), ArgParen(Args([yield])))
    end

    def sig_type_for(type)
      case type
      when Reflection::Type::ArrayType
        ARef(
          ConstPathRef(VarRef(Const("T")), Const("Array")),
          sig_type_for(type.type)
        )
      when Reflection::Type::TupleType
        ArrayLiteral(LBracket("["), Args(type.types.map { sig_type_for(_1) }))
      when Reflection::Type::UnionType
        if type.types.include?(NilClass)
          selected = type.types.reject { _1 == NilClass }
          subtype =
            if selected.size == 1
              selected.first
            else
              Reflection::Type::UnionType.new(selected)
            end

          CallNode(
            VarRef(Const("T")),
            Period("."),
            Ident("nilable"),
            ArgParen(Args([sig_type_for(subtype)]))
          )
        else
          CallNode(
            VarRef(Const("T")),
            Period("."),
            Ident("any"),
            ArgParen(Args(type.types.map { sig_type_for(_1) }))
          )
        end
      when Symbol
        ConstRef(Const("Symbol"))
      else
        *parents, constant = type.name.split("::").map { Const(_1) }

        if parents.empty?
          ConstRef(constant)
        else
          [*parents[1..], constant].inject(
            VarRef(parents.first)
          ) { |accum, const| ConstPathRef(accum, const) }
        end
      end
    end

    def location
      Location.fixed(line: line, char: 0, column: 0)
    end
  end
end

namespace :sorbet do
  desc "Generate RBI files for Sorbet"
  task :rbi do
    puts SyntaxTree::RBI.new.generate
  end
end
