# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This class is responsible for taking a compiled instruction sequence and
    # walking through it to generate equivalent Ruby code.
    class Disassembler
      # When we're disassmebling, we use a looped case statement to emulate
      # jumping around in the same way the virtual machine would. This class
      # provides convenience methods for generating the AST nodes that have to
      # do with that label.
      class DisasmLabel
        include DSL
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def field
          VarField(Ident(name))
        end

        def ref
          VarRef(Ident(name))
        end
      end

      include DSL
      attr_reader :iseq, :disasm_label

      def initialize(iseq)
        @iseq = iseq
        @disasm_label = DisasmLabel.new("__disasm_label")
      end

      def to_ruby
        Program(disassemble(iseq))
      end

      private

      def node_for(value)
        case value
        when Integer
          Int(value.to_s)
        when Symbol
          SymbolLiteral(Ident(value.to_s))
        end
      end

      def disassemble(iseq)
        label = :label_0
        clauses = {}
        clause = []

        iseq.insns.each do |insn|
          case insn
          when Symbol
            if insn.start_with?("label_")
              unless clause.last.is_a?(Next)
                clause << Assign(disasm_label.field, node_for(insn))
              end

              clauses[label] = clause
              clause = []
              label = insn
            end
          when BranchUnless
            body = [
              Assign(disasm_label.field, node_for(insn.label)),
              Next(Args([]))
            ]

            clause << IfNode(clause.pop, Statements(body), nil)
          when Dup
            clause << clause.last
          when DupHash
            assocs =
              insn.object.map do |key, value|
                Assoc(node_for(key), node_for(value))
              end

            clause << HashLiteral(LBrace("{"), assocs)
          when GetGlobal
            clause << VarRef(GVar(insn.name.to_s))
          when GetLocalWC0
            local = iseq.local_table.locals[insn.index]
            clause << VarRef(Ident(local.name.to_s))
          when Array
            case insn[0]
            when :jump
              clause << Assign(disasm_label.field, node_for(insn[1]))
              clause << Next(Args([]))
            when :leave
              value = Args([clause.pop])
              clause << (iseq.type == :top ? Break(value) : ReturnNode(value))
            when :opt_and
              left, right = clause.pop(2)
              clause << Binary(left, :&, right)
            when :opt_aref
              collection, arg = clause.pop(2)
              clause << ARef(collection, Args([arg]))
            when :opt_aset
              collection, arg, value = clause.pop(3)

              clause << if value.is_a?(Binary) && value.left.is_a?(ARef) &&
                   collection === value.left.collection &&
                   arg === value.left.index.parts[0]
                OpAssign(
                  ARefField(collection, Args([arg])),
                  Op("#{value.operator}="),
                  value.right
                )
              else
                Assign(ARefField(collection, Args([arg])), value)
              end
            when :opt_div
              left, right = clause.pop(2)
              clause << Binary(left, :/, right)
            when :opt_eq
              left, right = clause.pop(2)
              clause << Binary(left, :==, right)
            when :opt_ge
              left, right = clause.pop(2)
              clause << Binary(left, :>=, right)
            when :opt_gt
              left, right = clause.pop(2)
              clause << Binary(left, :>, right)
            when :opt_le
              left, right = clause.pop(2)
              clause << Binary(left, :<=, right)
            when :opt_lt
              left, right = clause.pop(2)
              clause << Binary(left, :<, right)
            when :opt_ltlt
              left, right = clause.pop(2)
              clause << Binary(left, :<<, right)
            when :opt_minus
              left, right = clause.pop(2)
              clause << Binary(left, :-, right)
            when :opt_mod
              left, right = clause.pop(2)
              clause << Binary(left, :%, right)
            when :opt_mult
              left, right = clause.pop(2)
              clause << Binary(left, :*, right)
            when :opt_neq
              left, right = clause.pop(2)
              clause << Binary(left, :"!=", right)
            when :opt_or
              left, right = clause.pop(2)
              clause << Binary(left, :|, right)
            when :opt_plus
              left, right = clause.pop(2)
              clause << Binary(left, :+, right)
            when :opt_send_without_block
              if insn[1][:flag] & VM_CALL_FCALL > 0
                if insn[1][:orig_argc] == 0
                  clause.pop
                  clause << CallNode(nil, nil, Ident(insn[1][:mid]), Args([]))
                elsif insn[1][:orig_argc] == 1 && insn[1][:mid].end_with?("=")
                  _receiver, argument = clause.pop(2)
                  clause << Assign(
                    CallNode(nil, nil, Ident(insn[1][:mid][0..-2]), nil),
                    argument
                  )
                else
                  _receiver, *arguments = clause.pop(insn[1][:orig_argc] + 1)
                  clause << CallNode(
                    nil,
                    nil,
                    Ident(insn[1][:mid]),
                    ArgParen(Args(arguments))
                  )
                end
              else
                if insn[1][:orig_argc] == 0
                  clause << CallNode(
                    clause.pop,
                    Period("."),
                    Ident(insn[1][:mid]),
                    nil
                  )
                elsif insn[1][:orig_argc] == 1 && insn[1][:mid].end_with?("=")
                  receiver, argument = clause.pop(2)
                  clause << Assign(
                    CallNode(
                      receiver,
                      Period("."),
                      Ident(insn[1][:mid][0..-2]),
                      nil
                    ),
                    argument
                  )
                else
                  receiver, *arguments = clause.pop(insn[1][:orig_argc] + 1)
                  clause << CallNode(
                    receiver,
                    Period("."),
                    Ident(insn[1][:mid]),
                    ArgParen(Args(arguments))
                  )
                end
              end
            when :putobject
              case insn[1]
              when Float
                clause << FloatLiteral(insn[1].inspect)
              when Integer
                clause << Int(insn[1].inspect)
              else
                raise "Unknown object type: #{insn[1].class.name}"
              end
            when :putobject_INT2FIX_0_
              clause << Int("0")
            when :putobject_INT2FIX_1_
              clause << Int("1")
            when :putself
              clause << VarRef(Kw("self"))
            when :setglobal
              target = GVar(insn[1].to_s)
              value = clause.pop

              clause << if value.is_a?(Binary) && VarRef(target) === value.left
                OpAssign(
                  VarField(target),
                  Op("#{value.operator}="),
                  value.right
                )
              else
                Assign(VarField(target), value)
              end
            when :setlocal_WC_0
              target = Ident(local_name(insn[1], 0))
              value = clause.pop

              clause << if value.is_a?(Binary) && VarRef(target) === value.left
                OpAssign(
                  VarField(target),
                  Op("#{value.operator}="),
                  value.right
                )
              else
                Assign(VarField(target), value)
              end
            else
              raise "Unknown instruction #{insn[0]}"
            end
          end
        end

        # If there's only one clause, then we don't need a case statement, and
        # we can just disassemble the first clause.
        clauses[label] = clause
        return Statements(clauses.values.first) if clauses.size == 1

        # Here we're going to build up a big case statement that will handle all
        # of the different labels.
        current = nil
        clauses.reverse_each do |current_label, current_clause|
          current =
            When(
              Args([node_for(current_label)]),
              Statements(current_clause),
              current
            )
        end
        switch = Case(Kw("case"), disasm_label.ref, current)

        # Here we're going to make sure that any locals that were established in
        # the label_0 block are initialized so that scoping rules work
        # correctly.
        stack = []
        locals = [disasm_label.name]

        clauses[:label_0].each do |node|
          if node.is_a?(Assign) && node.target.is_a?(VarField) &&
               node.target.value.is_a?(Ident)
            value = node.target.value.value
            next if locals.include?(value)

            stack << Assign(node.target, VarRef(Kw("nil")))
            locals << value
          end
        end

        # Finally, we'll set up the initial label and loop the entire case
        # statement.
        stack << Assign(disasm_label.field, node_for(:label_0))
        stack << MethodAddBlock(
          CallNode(nil, nil, Ident("loop"), Args([])),
          BlockNode(
            Kw("do"),
            nil,
            BodyStmt(Statements([switch]), nil, nil, nil, nil)
          )
        )
        Statements(stack)
      end

      def local_name(index, level)
        current = iseq
        level.times { current = current.parent_iseq }
        current.local_table.locals[index].name.to_s
      end
    end
  end
end
