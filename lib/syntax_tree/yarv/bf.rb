# frozen_string_literal: true

module SyntaxTree
  module YARV
    # Parses the given source code into a syntax tree, compiles that syntax tree
    # into YARV bytecode.
    class Bf
      attr_reader :source

      def initialize(source)
        @source = source
      end

      def compile
        # Set up the top-level instruction sequence that will be returned.
        iseq = InstructionSequence.new("<compiled>", "<compiled>", 1, :top)

        # Set up the $tape global variable that will hold our state.
        iseq.duphash({ 0 => 0 })
        iseq.setglobal(:$tape)
        iseq.getglobal(:$tape)
        iseq.putobject(0)
        iseq.send(YARV.calldata(:default=, 1))

        # Set up the $cursor global variable that will hold the current position
        # in the tape.
        iseq.putobject(0)
        iseq.setglobal(:$cursor)

        stack = []
        source
          .each_char
          .chunk do |char|
            # For each character, we're going to assign a type to it. This
            # allows a couple of optimizations to be made by combining multiple
            # instructions into single instructions, e.g., +++ becomes a single
            # change_by(3) instruction.
            case char
            when "+", "-"
              :change
            when ">", "<"
              :shift
            when "."
              :output
            when ","
              :input
            when "[", "]"
              :loop
            else
              :ignored
            end
          end
          .each do |type, chunk|
            # For each chunk, we're going to emit the appropriate instruction.
            case type
            when :change
              change_by(iseq, chunk.count("+") - chunk.count("-"))
            when :shift
              shift_by(iseq, chunk.count(">") - chunk.count("<"))
            when :output
              chunk.length.times { output_char(iseq) }
            when :input
              chunk.length.times { input_char(iseq) }
            when :loop
              chunk.each do |char|
                case char
                when "["
                  stack << loop_start(iseq)
                when "]"
                  loop_end(iseq, *stack.pop)
                end
              end
            end
          end

        iseq.leave
        iseq.compile!
        iseq
      end

      private

      # $tape[$cursor] += value
      def change_by(iseq, value)
        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)

        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)
        iseq.send(YARV.calldata(:[], 1))

        if value < 0
          iseq.putobject(-value)
          iseq.send(YARV.calldata(:-, 1))
        else
          iseq.putobject(value)
          iseq.send(YARV.calldata(:+, 1))
        end

        iseq.send(YARV.calldata(:[]=, 2))
        iseq.pop
      end

      # $cursor += value
      def shift_by(iseq, value)
        iseq.getglobal(:$cursor)

        if value < 0
          iseq.putobject(-value)
          iseq.send(YARV.calldata(:-, 1))
        else
          iseq.putobject(value)
          iseq.send(YARV.calldata(:+, 1))
        end

        iseq.setglobal(:$cursor)
      end

      # $stdout.putc($tape[$cursor].chr)
      def output_char(iseq)
        iseq.getglobal(:$stdout)

        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)
        iseq.send(YARV.calldata(:[], 1))
        iseq.send(YARV.calldata(:chr))

        iseq.send(YARV.calldata(:putc, 1))
        iseq.pop
      end

      # $tape[$cursor] = $stdin.getc.ord
      def input_char(iseq)
        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)

        iseq.getglobal(:$stdin)
        iseq.send(YARV.calldata(:getc))
        iseq.send(YARV.calldata(:ord))

        iseq.send(YARV.calldata(:[]=, 2))
        iseq.pop
      end

      # unless $tape[$cursor] == 0
      def loop_start(iseq)
        start_label = iseq.label
        end_label = iseq.label

        iseq.push(start_label)
        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)
        iseq.send(YARV.calldata(:[], 1))

        iseq.putobject(0)
        iseq.send(YARV.calldata(:==, 1))
        iseq.branchif(end_label)

        [start_label, end_label]
      end

      # Jump back to the start of the loop.
      def loop_end(iseq, start_label, end_label)
        iseq.getglobal(:$tape)
        iseq.getglobal(:$cursor)
        iseq.send(YARV.calldata(:[], 1))

        iseq.putobject(0)
        iseq.send(YARV.calldata(:==, 1))
        iseq.branchunless(start_label)

        iseq.push(end_label)
      end
    end
  end
end
