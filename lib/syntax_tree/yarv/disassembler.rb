# frozen_string_literal: true

module SyntaxTree
  module YARV
    class Disassembler
      attr_reader :output, :queue
      attr_reader :current_prefix
      attr_accessor :current_iseq

      def initialize
        @output = StringIO.new
        @queue = []

        @current_prefix = ""
        @current_iseq = nil
      end

      ########################################################################
      # Helpers for various instructions
      ########################################################################

      def calldata(value)
        flag_names = []
        flag_names << :ARGS_SPLAT if value.flag?(CallData::CALL_ARGS_SPLAT)
        if value.flag?(CallData::CALL_ARGS_BLOCKARG)
          flag_names << :ARGS_BLOCKARG
        end
        flag_names << :FCALL if value.flag?(CallData::CALL_FCALL)
        flag_names << :VCALL if value.flag?(CallData::CALL_VCALL)
        flag_names << :ARGS_SIMPLE if value.flag?(CallData::CALL_ARGS_SIMPLE)
        flag_names << :BLOCKISEQ if value.flag?(CallData::CALL_BLOCKISEQ)
        flag_names << :KWARG if value.flag?(CallData::CALL_KWARG)
        flag_names << :KW_SPLAT if value.flag?(CallData::CALL_KW_SPLAT)
        flag_names << :TAILCALL if value.flag?(CallData::CALL_TAILCALL)
        flag_names << :SUPER if value.flag?(CallData::CALL_SUPER)
        flag_names << :ZSUPER if value.flag?(CallData::CALL_ZSUPER)
        flag_names << :OPT_SEND if value.flag?(CallData::CALL_OPT_SEND)
        flag_names << :KW_SPLAT_MUT if value.flag?(CallData::CALL_KW_SPLAT_MUT)

        parts = []
        parts << "mid:#{value.method}" if value.method
        parts << "argc:#{value.argc}"
        parts << "kw:[#{value.kw_arg.join(", ")}]" if value.kw_arg
        parts << flag_names.join("|") if flag_names.any?

        "<calldata!#{parts.join(", ")}>"
      end

      def enqueue(iseq)
        queue << iseq
      end

      def event(name)
        case name
        when :RUBY_EVENT_B_CALL
          "Bc"
        when :RUBY_EVENT_B_RETURN
          "Br"
        when :RUBY_EVENT_CALL
          "Ca"
        when :RUBY_EVENT_CLASS
          "Cl"
        when :RUBY_EVENT_END
          "En"
        when :RUBY_EVENT_LINE
          "Li"
        when :RUBY_EVENT_RETURN
          "Re"
        else
          raise "Unknown event: #{name}"
        end
      end

      def inline_storage(cache)
        "<is:#{cache}>"
      end

      def instruction(name, operands = [])
        operands.empty? ? name : "%-38s %s" % [name, operands.join(", ")]
      end

      def label(value)
        value.name["label_".length..]
      end

      def local(index, explicit: nil, implicit: nil)
        current = current_iseq
        (explicit || implicit).times { current = current.parent_iseq }

        value = "#{current.local_table.name_at(index)}@#{index}"
        value << ", #{explicit}" if explicit
        value
      end

      def object(value)
        value.inspect
      end

      ########################################################################
      # Main entrypoint
      ########################################################################

      def format!
        while (@current_iseq = queue.shift)
          output << "\n" if output.pos > 0
          format_iseq(@current_iseq)
        end

        output.string
      end

      private

      def format_iseq(iseq)
        output << "#{current_prefix}== disasm: "
        output << "#<ISeq:#{iseq.name}@<compiled>:1 "

        location = Location.fixed(line: iseq.line, char: 0, column: 0)
        output << "(#{location.start_line},#{location.start_column})-"
        output << "(#{location.end_line},#{location.end_column})"
        output << "> "

        if iseq.catch_table.any?
          output << "(catch: TRUE)\n"
          output << "#{current_prefix}== catch table\n"

          with_prefix("#{current_prefix}| ") do
            iseq.catch_table.each do |entry|
              case entry
              when InstructionSequence::CatchBreak
                output << "#{current_prefix}catch type: break\n"
                format_iseq(entry.iseq)
              when InstructionSequence::CatchNext
                output << "#{current_prefix}catch type: next\n"
              when InstructionSequence::CatchRedo
                output << "#{current_prefix}catch type: redo\n"
              when InstructionSequence::CatchRescue
                output << "#{current_prefix}catch type: rescue\n"
                format_iseq(entry.iseq)
              end
            end
          end

          output << "#{current_prefix}|#{"-" * 72}\n"
        else
          output << "(catch: FALSE)\n"
        end

        if (local_table = iseq.local_table) && !local_table.empty?
          output << "#{current_prefix}local table (size: #{local_table.size})\n"

          locals =
            local_table.locals.each_with_index.map do |local, index|
              "[%2d] %s@%d" % [local_table.offset(index), local.name, index]
            end

          output << "#{current_prefix}#{locals.join("    ")}\n"
        end

        length = 0
        events = []
        lines = []

        iseq.insns.each do |insn|
          case insn
          when Integer
            lines << insn
          when Symbol
            events << event(insn)
          when InstructionSequence::Label
            # skip
          else
            output << "#{current_prefix}%04d " % length

            disasm = insn.disasm(self)
            output << disasm

            if lines.any?
              output << " " * (65 - disasm.length) if disasm.length < 65
            elsif events.any?
              output << " " * (39 - disasm.length) if disasm.length < 39
            end

            if lines.any?
              output << "(%4d)" % lines.last
              lines.clear
            end

            if events.any?
              output << "[#{events.join}]"
              events.clear
            end

            output << "\n"
            length += insn.length
          end
        end
      end

      def with_prefix(value)
        previous = @current_prefix

        begin
          @current_prefix = value
          yield
        ensure
          @current_prefix = previous
        end
      end
    end
  end
end
