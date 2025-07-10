# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This class is responsible for taking a compiled instruction sequence and
    # walking through it to generate equivalent Ruby code.
    class Decompiler
      # When we're decompiling, we use a looped case statement to emulate
      # jumping around in the same way the virtual machine would. This class
      # provides convenience methods for generating the AST nodes that have to
      # do with that label.
      class BlockLabel
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
      attr_reader :iseq, :block_label

      def initialize(iseq)
        @iseq = iseq
        @block_label = BlockLabel.new("__block_label")
      end

      def to_ruby
        Program(decompile(iseq))
      end

      private

      def node_for(value)
        case value
        when Integer
          Int(value.to_s)
        when Symbol
          SymbolLiteral(Ident(value.name))
        end
      end

      def decompile(iseq)
        label = :label_0
        clauses = {}
        clause = []

        iseq.insns.each do |insn|
          case insn
          when InstructionSequence::Label
            unless clause.last.is_a?(Next)
              clause << Assign(block_label.field, node_for(insn.name))
            end

            clauses[label] = clause
            clause = []
            label = insn.name
          when BranchIf
            body = [
              Assign(block_label.field, node_for(insn.label.name)),
              Next(Args([]))
            ]

            clause << UnlessNode(clause.pop, Statements(body), nil)
          when BranchUnless
            body = [
              Assign(block_label.field, node_for(insn.label.name)),
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
            clause << VarRef(GVar(insn.name.name))
          when GetLocalWC0
            local = iseq.local_table.locals[insn.index]
            clause << VarRef(Ident(local.name.name))
          when Jump
            clause << Assign(block_label.field, node_for(insn.label.name))
            clause << Next(Args([]))
          when Leave
            value = Args([clause.pop])
            clause << (iseq.type != :top ? Break(value) : ReturnNode(value))
          when OptAnd, OptDiv, OptEq, OptGE, OptGT, OptLE, OptLT, OptLTLT,
               OptMinus, OptMod, OptMult, OptOr, OptPlus
            left, right = clause.pop(2)
            clause << Binary(left, insn.calldata.method, right)
          when OptAref
            collection, arg = clause.pop(2)
            clause << ARef(collection, Args([arg]))
          when OptAset
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
          when OptNEq
            left, right = clause.pop(2)
            clause << Binary(left, :"!=", right)
          when OptSendWithoutBlock
            method = insn.calldata.method.name
            argc = insn.calldata.argc

            if insn.calldata.flag?(CallData::CALL_FCALL)
              if argc == 0
                clause.pop
                clause << CallNode(nil, nil, Ident(method), Args([]))
              elsif argc == 1 && method.end_with?("=")
                _receiver, argument = clause.pop(2)
                clause << Assign(
                  CallNode(nil, nil, Ident(method[0..-2]), nil),
                  argument
                )
              else
                _receiver, *arguments = clause.pop(argc + 1)
                clause << CallNode(
                  nil,
                  nil,
                  Ident(method),
                  ArgParen(Args(arguments))
                )
              end
            else
              if argc == 0
                clause << CallNode(clause.pop, Period("."), Ident(method), nil)
              elsif argc == 1 && method.end_with?("=")
                receiver, argument = clause.pop(2)
                clause << Assign(
                  Field(receiver, Period("."), Ident(method[0..-2])),
                  argument
                )
              else
                receiver, *arguments = clause.pop(argc + 1)
                clause << CallNode(
                  receiver,
                  Period("."),
                  Ident(method),
                  ArgParen(Args(arguments))
                )
              end
            end
          when Pop
            # skip
          when PutObject
            case insn.object
            when Float
              clause << FloatLiteral(insn.object.inspect)
            when Integer
              clause << Int(insn.object.inspect)
            else
              raise "Unknown object type: #{insn.object.class.name}"
            end
          when PutObjectInt2Fix0
            clause << Int("0")
          when PutObjectInt2Fix1
            clause << Int("1")
          when PutSelf
            clause << VarRef(Kw("self"))
          when SetGlobal
            target = GVar(insn.name.name)
            value = clause.pop

            clause << if value.is_a?(Binary) && VarRef(target) === value.left
              OpAssign(VarField(target), Op("#{value.operator}="), value.right)
            else
              Assign(VarField(target), value)
            end
          when SetLocalWC0
            target = Ident(local_name(insn.index, 0))
            value = clause.pop

            clause << if value.is_a?(Binary) && VarRef(target) === value.left
              OpAssign(VarField(target), Op("#{value.operator}="), value.right)
            else
              Assign(VarField(target), value)
            end
          else
            raise "Unknown instruction #{insn}"
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
        switch = Case(Kw("case"), block_label.ref, current)

        # Here we're going to make sure that any locals that were established in
        # the label_0 block are initialized so that scoping rules work
        # correctly.
        stack = []
        locals = [block_label.name]

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
        stack << Assign(block_label.field, node_for(:label_0))
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
        current.local_table.locals[index].name.name
      end
    end
  end
end
