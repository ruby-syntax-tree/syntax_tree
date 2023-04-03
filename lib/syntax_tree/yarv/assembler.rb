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

      CALLDATA_FLAGS = {
        "ARGS_SPLAT" => CallData::CALL_ARGS_SPLAT,
        "ARGS_BLOCKARG" => CallData::CALL_ARGS_BLOCKARG,
        "FCALL" => CallData::CALL_FCALL,
        "VCALL" => CallData::CALL_VCALL,
        "ARGS_SIMPLE" => CallData::CALL_ARGS_SIMPLE,
        "KWARG" => CallData::CALL_KWARG,
        "KW_SPLAT" => CallData::CALL_KW_SPLAT,
        "TAILCALL" => CallData::CALL_TAILCALL,
        "SUPER" => CallData::CALL_SUPER,
        "ZSUPER" => CallData::CALL_ZSUPER,
        "OPT_SEND" => CallData::CALL_OPT_SEND,
        "KW_SPLAT_MUT" => CallData::CALL_KW_SPLAT_MUT
      }.freeze

      DEFINED_TYPES = [
        nil,
        "nil",
        "instance-variable",
        "local-variable",
        "global-variable",
        "class variable",
        "constant",
        "method",
        "yield",
        "super",
        "self",
        "true",
        "false",
        "assignment",
        "expression",
        "ref",
        "func",
        "constant-from"
      ].freeze

      attr_reader :lines

      def initialize(lines)
        @lines = lines
      end

      def assemble
        iseq = InstructionSequence.new("<main>", "<compiled>", 1, :top)
        assemble_iseq(iseq, lines)

        iseq.compile!
        iseq
      end

      def self.assemble(source)
        new(source.lines(chomp: true)).assemble
      end

      def self.assemble_file(filepath)
        new(File.readlines(filepath, chomp: true)).assemble
      end

      private

      def assemble_iseq(iseq, lines)
        labels = Hash.new { |hash, name| hash[name] = iseq.label }
        line_index = 0

        while line_index < lines.length
          line = lines[line_index]
          line_index += 1

          case line.strip
          when "", /^;/
            # skip over blank lines and comments
            next
          when /^(\w+):$/
            # create labels
            iseq.push(labels[$1])
            next
          when /^__END__/
            # skip over the rest of the file when we hit __END__
            return
          end

          insn, operands = line.split(" ", 2)

          case insn
          when "adjuststack"
            iseq.adjuststack(parse_number(operands))
          when "anytostring"
            iseq.anytostring
          when "branchif"
            iseq.branchif(labels[operands])
          when "branchnil"
            iseq.branchnil(labels[operands])
          when "branchunless"
            iseq.branchunless(labels[operands])
          when "checkkeyword"
            kwbits_index, keyword_index = operands.split(/,\s*/)
            iseq.checkkeyword(
              parse_number(kwbits_index),
              parse_number(keyword_index)
            )
          when "checkmatch"
            iseq.checkmatch(parse_number(operands))
          when "checktype"
            iseq.checktype(parse_number(operands))
          when "concatarray"
            iseq.concatarray
          when "concatstrings"
            iseq.concatstrings(parse_number(operands))
          when "defineclass"
            body = parse_nested(lines[line_index..])
            line_index += body.length

            name_value, flags_value = operands.split(/,\s*/)
            name = parse_symbol(name_value)
            flags = parse_number(flags_value)

            class_iseq = iseq.class_child_iseq(name.to_s, 1)
            assemble_iseq(class_iseq, body)
            iseq.defineclass(name, class_iseq, flags)
          when "defined"
            type, object, message = operands.split(/,\s*/)
            iseq.defined(
              DEFINED_TYPES.index(type),
              parse_symbol(object),
              parse_string(message)
            )
          when "definemethod"
            body = parse_nested(lines[line_index..])
            line_index += body.length

            name = parse_symbol(operands)
            method_iseq = iseq.method_child_iseq(name.to_s, 1)
            assemble_iseq(method_iseq, body)

            iseq.definemethod(name, method_iseq)
          when "definesmethod"
            body = parse_nested(lines[line_index..])
            line_index += body.length

            name = parse_symbol(operands)
            method_iseq = iseq.method_child_iseq(name.to_s, 1)

            assemble_iseq(method_iseq, body)
            iseq.definesmethod(name, method_iseq)
          when "dup"
            iseq.dup
          when "dupn"
            iseq.dupn(parse_number(operands))
          when "duparray"
            iseq.duparray(parse_type(operands, Array))
          when "duphash"
            iseq.duphash(parse_type(operands, Hash))
          when "expandarray"
            number, flags = operands.split(/,\s*/)
            iseq.expandarray(parse_number(number), parse_number(flags))
          when "getblockparam"
            lookup = find_local(iseq, operands)
            iseq.getblockparam(lookup.index, lookup.level)
          when "getblockparamproxy"
            lookup = find_local(iseq, operands)
            iseq.getblockparamproxy(lookup.index, lookup.level)
          when "getclassvariable"
            iseq.getclassvariable(parse_symbol(operands))
          when "getconstant"
            iseq.getconstant(parse_symbol(operands))
          when "getglobal"
            iseq.getglobal(parse_symbol(operands))
          when "getinstancevariable"
            iseq.getinstancevariable(parse_symbol(operands))
          when "getlocal"
            lookup = find_local(iseq, operands)
            iseq.getlocal(lookup.index, lookup.level)
          when "getspecial"
            key, type = operands.split(/,\s*/)
            iseq.getspecial(parse_number(key), parse_number(type))
          when "intern"
            iseq.intern
          when "invokeblock"
            iseq.invokeblock(
              operands ? parse_calldata(operands) : YARV.calldata(nil, 0)
            )
          when "invokesuper"
            calldata =
              if operands
                parse_calldata(operands)
              else
                YARV.calldata(
                  nil,
                  0,
                  CallData::CALL_FCALL | CallData::CALL_ARGS_SIMPLE |
                    CallData::CALL_SUPER
                )
              end

            block_iseq =
              if lines[line_index].start_with?("  ")
                body = parse_nested(lines[line_index..])
                line_index += body.length

                block_iseq = iseq.block_child_iseq(1)
                assemble_iseq(block_iseq, body)
                block_iseq
              end

            iseq.invokesuper(calldata, block_iseq)
          when "jump"
            iseq.jump(labels[operands])
          when "leave"
            iseq.leave
          when "newarray"
            iseq.newarray(parse_number(operands))
          when "newarraykwsplat"
            iseq.newarraykwsplat(parse_number(operands))
          when "newhash"
            iseq.newhash(parse_number(operands))
          when "newrange"
            iseq.newrange(parse_options(operands, [0, 1]))
          when "nop"
            iseq.nop
          when "objtostring"
            iseq.objtostring(YARV.calldata(:to_s))
          when "once"
            block_iseq =
              if lines[line_index].start_with?("  ")
                body = parse_nested(lines[line_index..])
                line_index += body.length

                block_iseq = iseq.block_child_iseq(1)
                assemble_iseq(block_iseq, body)
                block_iseq
              end

            iseq.once(block_iseq, iseq.inline_storage)
          when "opt_and"
            iseq.send(YARV.calldata(:&, 1))
          when "opt_aref"
            iseq.send(YARV.calldata(:[], 1))
          when "opt_aref_with"
            iseq.opt_aref_with(parse_string(operands), YARV.calldata(:[], 1))
          when "opt_aset"
            iseq.send(YARV.calldata(:[]=, 2))
          when "opt_aset_with"
            iseq.opt_aset_with(parse_string(operands), YARV.calldata(:[]=, 2))
          when "opt_case_dispatch"
            cdhash_value, else_label_value = operands.split(/\s*\},\s*/)
            cdhash_value.sub!(/\A\{/, "")

            pairs =
              cdhash_value
                .split(/\s*,\s*/)
                .map! { |pair| pair.split(/\s*=>\s*/) }

            cdhash = pairs.to_h { |value, nm| [parse(value), labels[nm]] }
            else_label = labels[else_label_value]

            iseq.opt_case_dispatch(cdhash, else_label)
          when "opt_div"
            iseq.send(YARV.calldata(:/, 1))
          when "opt_empty_p"
            iseq.send(YARV.calldata(:empty?))
          when "opt_eq"
            iseq.send(YARV.calldata(:==, 1))
          when "opt_ge"
            iseq.send(YARV.calldata(:>=, 1))
          when "opt_gt"
            iseq.send(YARV.calldata(:>, 1))
          when "opt_getconstant_path"
            iseq.opt_getconstant_path(parse_type(operands, Array))
          when "opt_le"
            iseq.send(YARV.calldata(:<=, 1))
          when "opt_length"
            iseq.send(YARV.calldata(:length))
          when "opt_lt"
            iseq.send(YARV.calldata(:<, 1))
          when "opt_ltlt"
            iseq.send(YARV.calldata(:<<, 1))
          when "opt_minus"
            iseq.send(YARV.calldata(:-, 1))
          when "opt_mod"
            iseq.send(YARV.calldata(:%, 1))
          when "opt_mult"
            iseq.send(YARV.calldata(:*, 1))
          when "opt_neq"
            iseq.send(YARV.calldata(:!=, 1))
          when "opt_newarray_max"
            iseq.newarray(parse_number(operands))
            iseq.send(YARV.calldata(:max))
          when "opt_newarray_min"
            iseq.newarray(parse_number(operands))
            iseq.send(YARV.calldata(:min))
          when "opt_nil_p"
            iseq.send(YARV.calldata(:nil?))
          when "opt_not"
            iseq.send(YARV.calldata(:!))
          when "opt_or"
            iseq.send(YARV.calldata(:|, 1))
          when "opt_plus"
            iseq.send(YARV.calldata(:+, 1))
          when "opt_regexpmatch2"
            iseq.send(YARV.calldata(:=~, 1))
          when "opt_reverse"
            iseq.send(YARV.calldata(:reverse))
          when "opt_send_without_block"
            iseq.send(parse_calldata(operands))
          when "opt_size"
            iseq.send(YARV.calldata(:size))
          when "opt_str_freeze"
            iseq.putstring(parse_string(operands))
            iseq.send(YARV.calldata(:freeze))
          when "opt_str_uminus"
            iseq.putstring(parse_string(operands))
            iseq.send(YARV.calldata(:-@))
          when "opt_succ"
            iseq.send(YARV.calldata(:succ))
          when "pop"
            iseq.pop
          when "putnil"
            iseq.putnil
          when "putobject"
            iseq.putobject(parse(operands))
          when "putself"
            iseq.putself
          when "putspecialobject"
            iseq.putspecialobject(parse_options(operands, [1, 2, 3]))
          when "putstring"
            iseq.putstring(parse_string(operands))
          when "send"
            block_iseq =
              if lines[line_index].start_with?("  ")
                body = parse_nested(lines[line_index..])
                line_index += body.length

                block_iseq = iseq.block_child_iseq(1)
                assemble_iseq(block_iseq, body)
                block_iseq
              end

            iseq.send(parse_calldata(operands), block_iseq)
          when "setblockparam"
            lookup = find_local(iseq, operands)
            iseq.setblockparam(lookup.index, lookup.level)
          when "setconstant"
            iseq.setconstant(parse_symbol(operands))
          when "setglobal"
            iseq.setglobal(parse_symbol(operands))
          when "setlocal"
            lookup = find_local(iseq, operands)
            iseq.setlocal(lookup.index, lookup.level)
          when "setn"
            iseq.setn(parse_number(operands))
          when "setclassvariable"
            iseq.setclassvariable(parse_symbol(operands))
          when "setinstancevariable"
            iseq.setinstancevariable(parse_symbol(operands))
          when "setspecial"
            iseq.setspecial(parse_number(operands))
          when "splatarray"
            iseq.splatarray(parse_options(operands, [true, false]))
          when "swap"
            iseq.swap
          when "throw"
            iseq.throw(parse_number(operands))
          when "topn"
            iseq.topn(parse_number(operands))
          when "toregexp"
            options, length = operands.split(", ")
            iseq.toregexp(parse_number(options), parse_number(length))
          when "ARG_REQ"
            iseq.argument_size += 1
            iseq.local_table.plain(operands.to_sym)
          when "ARG_BLOCK"
            iseq.argument_options[:block_start] = iseq.argument_size
            iseq.local_table.block(operands.to_sym)
            iseq.argument_size += 1
          else
            raise "Could not understand: #{line}"
          end
        end
      end

      def find_local(iseq, operands)
        name_string, level_string = operands.split(/,\s*/)
        name = name_string.to_sym
        level = level_string&.to_i || 0

        iseq.local_table.plain(name)
        iseq.local_table.find(name, level)
      end

      def parse(value)
        program = SyntaxTree.parse(value)
        raise if program.statements.body.length != 1

        program.statements.body.first.accept(ObjectVisitor.new)
      end

      def parse_options(value, options)
        parse(value).tap { raise unless options.include?(_1) }
      end

      def parse_type(value, type)
        parse(value).tap { raise unless _1.is_a?(type) }
      end

      def parse_number(value)
        parse_type(value, Integer)
      end

      def parse_string(value)
        parse_type(value, String)
      end

      def parse_symbol(value)
        parse_type(value, Symbol)
      end

      def parse_nested(lines)
        body = lines.take_while { |line| line.match?(/^($|;|  )/) }
        body.map! { |line| line.delete_prefix!("  ") || +"" }
      end

      def parse_calldata(value)
        message, argc_value, flags_value = value.split
        flags =
          if flags_value
            flags_value.split("|").map(&CALLDATA_FLAGS).inject(:|)
          else
            CallData::CALL_ARGS_SIMPLE
          end

        YARV.calldata(message.to_sym, argc_value&.to_i || 0, flags)
      end
    end
  end
end
