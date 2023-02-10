# frozen_string_literal: true

module SyntaxTree
  module YARV
    class Disassembler
      # This class is another object that handles disassembling a YARV
      # instruction sequence but it renders it without any of the extra spacing
      # or alignment.
      class Squished
        def calldata(value)
          value.inspect
        end

        def enqueue(iseq)
        end

        def event(name)
        end

        def inline_storage(cache)
          "<is:#{cache}>"
        end

        def instruction(name, operands = [])
          operands.empty? ? name : "#{name} #{operands.join(", ")}"
        end

        def label(value)
          "%04d" % value.name["label_".length..]
        end

        def local(index, **)
          index.inspect
        end

        def object(value)
          value.inspect
        end
      end

      attr_reader :output, :queue

      attr_reader :current_prefix
      attr_accessor :current_iseq

      def initialize(current_iseq = nil)
        @output = StringIO.new
        @queue = []

        @current_prefix = ""
        @current_iseq = current_iseq
      end

      ########################################################################
      # Helpers for various instructions
      ########################################################################

      def calldata(value)
        value.inspect
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
      # Entrypoints
      ########################################################################

      def format!
        while (@current_iseq = queue.shift)
          output << "\n" if output.pos > 0
          format_iseq(@current_iseq)
        end
      end

      def format_insns!(insns, length = 0)
        events = []
        lines = []

        insns.each do |insn|
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

            # A hook here to allow for custom formatting of instructions after
            # the main body has been processed.
            yield insn, length if block_given?

            output << "\n"
            length += insn.length
          end
        end
      end

      def print(string)
        output.print(string)
      end

      def puts(string)
        output.puts(string)
      end

      def string
        output.string
      end

      def with_prefix(value)
        previous = @current_prefix

        begin
          @current_prefix = value
          yield value
        ensure
          @current_prefix = previous
        end
      end

      private

      def format_iseq(iseq)
        output << "#{current_prefix}== disasm: #{iseq.inspect} "

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

        format_insns!(iseq.insns)
      end
    end
  end
end
