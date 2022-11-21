# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This class is responsible for taking a compiled instruction sequence and
    # walking through it to generate equivalent Ruby code.
    class Disassembler
      include DSL
      attr_reader :iseq, :label_name, :label_field, :label_ref

      def initialize(iseq)
        @iseq = iseq

        @label_name = "__disasm_label"
        @label_field = VarField(Ident(label_name))
        @label_ref = VarRef(Ident(label_name))
      end

      def to_ruby
        Program(Statements(disassemble(iseq.insns)))
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

      def disassemble(insns)
        label = :label_0
        clauses = {}
        clause = []

        insns.each do |insn|
          if insn.is_a?(Symbol) && insn.start_with?("label_")
            clause << Assign(label_field, node_for(insn)) unless clause.last.is_a?(Next)
            clauses[label] = clause
            clause = []
            label = insn
            next
          end

          case insn[0]
          when :branchunless
            clause << IfNode(clause.pop, Statements([Assign(label_field, node_for(insn[1])), Next(Args([]))]), nil)
          when :dup
            clause << clause.last
          when :duphash
            assocs = insn[1].map { |key, value| Assoc(node_for(key), node_for(value)) }
            clause << HashLiteral(LBrace("{"), assocs)
          when :getglobal
            clause << VarRef(GVar(insn[1].to_s))
          when :getlocal_WC_0
            clause << VarRef(Ident(local_name(insn[1], 0)))
          when :jump
            clause << Assign(label_field, node_for(insn[1]))
            clause << Next(Args([]))
          when :leave
            clause << ReturnNode(Args([clause.pop]))
          when :opt_and
            left, right = clause.pop(2)
            clause << Binary(left, :&, right)
          when :opt_aref
            collection, arg = clause.pop(2)
            clause << ARef(collection, Args([arg]))
          when :opt_aset
            collection, arg, value = clause.pop(3)

            if value.is_a?(Binary) && value.left.is_a?(ARef) && collection === value.left.collection && arg === value.left.index.parts[0]
              clause << OpAssign(ARefField(collection, Args([arg])), Op("#{value.operator}="), value.right)
            else
              clause << Assign(ARefField(collection, Args([arg])), value)
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
            if insn[1][:orig_argc] == 0
              clause << CallNode(clause.pop, Period("."), Ident(insn[1][:mid]), nil)
            elsif insn[1][:orig_argc] == 1 && insn[1][:mid].end_with?("=")
              receiver, argument = clause.pop(2)
              clause << Assign(CallNode(receiver, Period("."), Ident(insn[1][:mid][0..-2]), nil), argument)
            else
              receiver, *arguments = clause.pop(insn[1][:orig_argc] + 1)
              clause << CallNode(receiver, Period("."), Ident(insn[1][:mid]), ArgParen(Args(arguments)))
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

            if value.is_a?(Binary) && VarRef(target) === value.left
              clause << OpAssign(VarField(target), Op("#{value.operator}="), value.right)
            else
              clause << Assign(VarField(target), value)
            end
          when :setlocal_WC_0
            target = Ident(local_name(insn[1], 0))
            value = clause.pop

            if value.is_a?(Binary) && VarRef(target) === value.left
              clause << OpAssign(VarField(target), Op("#{value.operator}="), value.right)
            else
              clause << Assign(VarField(target), value)
            end
          else
            raise "Unknown instruction #{insn[0]}"
          end
        end

        # If there's only one clause, then we don't need a case statement, and
        # we can just disassemble the first clause.
        clauses[label] = clause
        return clauses.values.first if clauses.size == 1

        # Here we're going to build up a big case statement that will handle all
        # of the different labels.
        current = nil
        clauses.reverse_each do |label, clause|
          current = When(Args([node_for(label)]), Statements(clause), current)
        end
        switch = Case(Kw("case"), label_ref, current)

        # Here we're going to make sure that any locals that were established in
        # the label_0 block are initialized so that scoping rules work
        # correctly.
        stack = []
        locals = [label_name]

        clauses[:label_0].each do |node|
          if node.is_a?(Assign) && node.target.is_a?(VarField) && node.target.value.is_a?(Ident)
            value = node.target.value.value
            next if locals.include?(value)

            stack << Assign(node.target, VarRef(Kw("nil")))
            locals << value 
          end
        end

        # Finally, we'll set up the initial label and loop the entire case
        # statement.
        stack << Assign(label_field, node_for(:label_0))
        stack << MethodAddBlock(CallNode(nil, nil, Ident("loop"), Args([])), BlockNode(Kw("do"), nil, BodyStmt(Statements([switch]), nil, nil, nil, nil)))
        stack
      end

      def local_name(index, level)
        current = iseq
        level.times { current = current.parent_iseq }
        current.local_table.locals[index].name.to_s
      end
    end
  end
end
