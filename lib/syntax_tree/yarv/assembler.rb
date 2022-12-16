# frozen_string_literal: true

module SyntaxTree
  module YARV
    class Assembler
      class ObjectVisitor < Compiler::RubyVisitor
        def visit_dyna_symbol(node)
          if node.parts.empty?
            :""
          else
            raise CompilationError
          end
        end

        def visit_string_literal(node)
          case node.parts.length
          when 0
            ""
          when 1
            raise CompilationError unless node.parts.first.is_a?(TStringContent)
            node.parts.first.value
          else
            raise CompilationError
          end
        end
      end

      attr_reader :filepath

      def initialize(filepath)
        @filepath = filepath
      end

      def assemble
        iseq = InstructionSequence.new(:top, "<main>", nil, Location.default)
        labels = {}

        File.foreach(filepath, chomp: true) do |line|
          case line.strip
          when ""
            # skip over blank lines
            next
          when /^;/
            # skip over comments
            next
          when /^(\w+):$/
            # create labels
            iseq.push(labels[$1] = iseq.label)
            next
          end

          insn, operands = line.split(" ", 2)

          case insn
          when "adjuststack"
            iseq.adjuststack(parse_number(operands))
          when "anytostring"
            iseq.anytostring
          when "checkmatch"
            iseq.checkmatch(parse_number(operands))
          when "checktype"
            iseq.checktype(parse_number(operands))
          when "concatarray"
            iseq.concatarray
          when "concatstrings"
            iseq.concatstrings(parse_number(operands))
          when "dup"
            iseq.dup
          when "dupn"
            iseq.dupn(parse_number(operands))
          when "duparray"
            object = parse(operands)
            raise unless object.is_a?(Array)

            iseq.duparray(object)
          when "duphash"
            object = parse(operands)
            raise unless object.is_a?(Hash)

            iseq.duphash(object)
          when "getinstancevariable"
            object = parse(operands)
            raise unless object.is_a?(Symbol)

            iseq.getinstancevariable(object)
          when "intern"
            iseq.intern
          when "leave"
            iseq.leave
          when "newarray"
            iseq.newarray(parse_number(operands))
          when "newrange"
            object = parse(operands)
            raise if object != 0 && object != 1

            iseq.newrange(operands.to_i)
          when "nop"
            iseq.nop
          when "objtostring"
            iseq.objtostring(
              YARV.calldata(
                :to_s,
                0,
                CallData::CALL_ARGS_SIMPLE | CallData::CALL_FCALL
              )
            )
          when "opt_and"
            iseq.send(YARV.calldata(:&, 1))
          when "opt_aref"
            iseq.send(YARV.calldata(:[], 1))
          when "opt_aref_with"
            object = parse(operands)
            raise unless object.is_a?(String)

            iseq.opt_aref_with(object, YARV.calldata(:[], 1))
          when "opt_div"
            iseq.send(YARV.calldata(:/, 1))
          when "opt_empty_p"
            iseq.send(
              YARV.calldata(
                :empty?,
                0,
                CallData::CALL_ARGS_SIMPLE | CallData::CALL_FCALL
              )
            )
          when "opt_eqeq"
            iseq.send(YARV.calldata(:==, 1))
          when "opt_ge"
            iseq.send(YARV.calldata(:>=, 1))
          when "opt_getconstant_path"
            object = parse(operands)
            raise unless object.is_a?(Array)

            iseq.opt_getconstant_path(object)
          when "opt_ltlt"
            iseq.send(YARV.calldata(:<<, 1))
          when "opt_minus"
            iseq.send(YARV.calldata(:-, 1))
          when "opt_mult"
            iseq.send(YARV.calldata(:*, 1))
          when "opt_or"
            iseq.send(YARV.calldata(:|, 1))
          when "opt_plus"
            iseq.send(YARV.calldata(:+, 1))
          when "pop"
            iseq.pop
          when "putnil"
            iseq.putnil
          when "putobject"
            iseq.putobject(parse(operands))
          when "putself"
            iseq.putself
          when "putstring"
            object = parse(operands)
            raise unless object.is_a?(String)

            iseq.putstring(object)
          when "send"
            iseq.send(calldata(operands))
          when "setinstancevariable"
            object = parse(operands)
            raise unless object.is_a?(Symbol)

            iseq.setinstancevariable(object)
          when "swap"
            iseq.swap
          when "toregexp"
            options, length = operands.split(", ")
            iseq.toregexp(parse_number(options), parse_number(length))
          else
            raise "Could not understand: #{line}"
          end
        end

        iseq.compile!
        iseq
      end

      def self.assemble(filepath)
        new(filepath).assemble
      end

      private

      def parse(value)
        program = SyntaxTree.parse(value)
        raise if program.statements.body.length != 1

        program.statements.body.first.accept(ObjectVisitor.new)
      end

      def parse_number(value)
        object = parse(value)
        raise unless object.is_a?(Integer)

        object
      end

      def calldata(value)
        message, argc_value, flags_value = value.split
        flags =
          if flags_value
            flags_value
              .split("|")
              .map do |flag|
                case flag
                when "ARGS_SPLAT"
                  CallData::CALL_ARGS_SPLAT
                when "ARGS_BLOCKARG"
                  CallData::CALL_ARGS_BLOCKARG
                when "FCALL"
                  CallData::CALL_FCALL
                when "VCALL"
                  CallData::CALL_VCALL
                when "ARGS_SIMPLE"
                  CallData::CALL_ARGS_SIMPLE
                when "BLOCKISEQ"
                  CallData::CALL_BLOCKISEQ
                when "KWARG"
                  CallData::CALL_KWARG
                when "KW_SPLAT"
                  CallData::CALL_KW_SPLAT
                when "TAILCALL"
                  CallData::CALL_TAILCALL
                when "SUPER"
                  CallData::CALL_SUPER
                when "ZSUPER"
                  CallData::CALL_ZSUPER
                when "OPT_SEND"
                  CallData::CALL_OPT_SEND
                when "KW_SPLAT_MUT"
                  CallData::CALL_KW_SPLAT_MUT
                end
              end
              .inject(:|)
          else
            CallData::CALL_ARGS_SIMPLE
          end

        YARV.calldata(message.to_sym, argc_value&.to_i || 0, flags)
      end
    end
  end
end
