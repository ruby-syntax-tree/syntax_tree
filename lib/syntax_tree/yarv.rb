# frozen_string_literal: true

require "forwardable"

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    class VM
      class Jump
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      class Leave
        attr_reader :value

        def initialize(value)
          @value = value
        end
      end

      class Frame
        attr_reader :iseq, :parent, :stack_index, :_self, :nesting, :svars

        def initialize(iseq, parent, stack_index, _self, nesting)
          @iseq = iseq
          @parent = parent
          @stack_index = stack_index
          @_self = _self
          @nesting = nesting
          @svars = {}
        end
      end

      class TopFrame < Frame
        def initialize(iseq)
          super(iseq, nil, 0, TOPLEVEL_BINDING.eval("self"), [Object])
        end
      end

      class BlockFrame < Frame
        def initialize(iseq, parent, stack_index)
          super(iseq, parent, stack_index, parent._self, parent.nesting)
        end
      end

      class MethodFrame < Frame
        attr_reader :name, :block

        def initialize(iseq, parent, stack_index, _self, name, block)
          super(iseq, parent, stack_index, _self, parent.nesting)
          @name = name
          @block = block
        end
      end

      class ClassFrame < Frame
        def initialize(iseq, parent, stack_index, _self)
          super(iseq, parent, stack_index, _self, parent.nesting + [_self])
        end
      end

      class FrozenCore
        define_method("core#hash_merge_kwd") { |left, right| left.merge(right) }

        define_method("core#hash_merge_ptr") do |hash, *values|
          hash.merge(values.each_slice(2).to_h)
        end

        define_method("core#set_method_alias") do |clazz, new_name, old_name|
          clazz.alias_method(new_name, old_name)
        end

        define_method("core#set_variable_alias") do |new_name, old_name|
          # Using eval here since there isn't a reflection API to be able to
          # alias global variables.
          eval("alias #{new_name} #{old_name}", binding, __FILE__, __LINE__)
        end

        define_method("core#set_postexe") { |&block| END { block.call } }

        define_method("core#undef_method") do |clazz, name|
          clazz.undef_method(name)
        end
      end

      FROZEN_CORE = FrozenCore.new.freeze

      extend Forwardable

      attr_reader :stack
      def_delegators :stack, :push, :pop

      attr_reader :frame
      def_delegators :frame, :_self

      def initialize
        @stack = []
        @frame = nil
      end

      ##########################################################################
      # Helper methods for frames
      ##########################################################################

      def run_frame(frame)
        # First, set the current frame to the given value.
        @frame = frame

        # Next, set up the local table for the frame. This is actually incorrect
        # as it could use the values already on the stack, but for now we're
        # just doing this for simplicity.
        frame.iseq.local_table.size.times { push(nil) }

        # Yield so that some frame-specific setup can be done.
        yield if block_given?

        # This hash is going to hold a mapping of label names to their
        # respective indices in our instruction list.
        labels = {}

        # This array is going to hold our instructions.
        insns = []

        # Here we're going to preprocess the instruction list from the
        # instruction sequence to set up the labels hash and the insns array.
        frame.iseq.insns.each do |insn|
          case insn
          when Integer, Symbol
            # skip
          when InstructionSequence::Label
            labels[insn.name] = insns.length
          else
            insns << insn
          end
        end

        # Finally we can execute the instructions one at a time. If they return
        # jumps or leaves we will handle those appropriately.
        pc = 0
        while pc < insns.length
          insn = insns[pc]
          pc += 1

          case (result = insn.call(self))
          when Jump
            pc = labels[result.name]
          when Leave
            return result.value
          end
        end
      ensure
        @stack = stack[0...frame.stack_index]
        @frame = frame.parent
      end

      def run_top_frame(iseq)
        run_frame(TopFrame.new(iseq))
      end

      def run_block_frame(iseq, *args, &block)
        run_frame(BlockFrame.new(iseq, frame, stack.length)) do
          locals = [*args, block]
          iseq.local_table.size.times do |index|
            local_set(index, 0, locals.shift)
          end
        end
      end

      def run_class_frame(iseq, clazz)
        run_frame(ClassFrame.new(iseq, frame, stack.length, clazz))
      end

      def run_method_frame(name, iseq, _self, *args, **kwargs, &block)
        run_frame(
          MethodFrame.new(iseq, frame, stack.length, _self, name, block)
        ) do
          locals = [*args, block]

          if iseq.argument_options[:keyword]
            # First, set up the keyword bits array.
            keyword_bits =
              iseq.argument_options[:keyword].map do |config|
                kwargs.key?(config.is_a?(Array) ? config[0] : config)
              end

            iseq.local_table.locals.each_with_index do |local, index|
              # If this is the keyword bits local, then set it appropriately.
              if local.name == 2
                locals.insert(index, keyword_bits)
                next
              end

              # First, find the configuration for this local in the keywords
              # list if it exists.
              name = local.name
              config =
                iseq.argument_options[:keyword].find do |keyword|
                  keyword.is_a?(Array) ? keyword[0] == name : keyword == name
                end

              # If the configuration doesn't exist, then the local is not a
              # keyword local.
              next unless config

              if !config.is_a?(Array)
                # required keyword
                locals.insert(index, kwargs.fetch(name))
              elsif !config[1].nil?
                # optional keyword with embedded default value
                locals.insert(index, kwargs.fetch(name, config[1]))
              else
                # optional keyword with expression default value
                locals.insert(index, nil)
              end
            end
          end

          iseq.local_table.size.times do |index|
            local_set(index, 0, locals.shift)
          end
        end
      end

      ##########################################################################
      # Helper methods for instructions
      ##########################################################################

      def const_base
        frame.nesting.last
      end

      def frame_at(level)
        current = frame
        level.times { current = current.parent }
        current
      end

      def frame_svar
        current = frame
        current = current.parent while current.is_a?(BlockFrame)
        current
      end

      def frame_yield
        current = frame
        current = current.parent until current.is_a?(MethodFrame)
        current
      end

      def frozen_core
        FROZEN_CORE
      end

      def jump(label)
        Jump.new(label.name)
      end

      def leave
        Leave.new(pop)
      end

      def local_get(index, level)
        stack[frame_at(level).stack_index + index]
      end

      def local_set(index, level, value)
        stack[frame_at(level).stack_index + index] = value
      end
    end

    # Compile the given source into a YARV instruction sequence.
    def self.compile(source, options = Compiler::Options.new)
      SyntaxTree.parse(source).accept(Compiler.new(options))
    end

    # Compile and interpret the given source.
    def self.interpret(source, options = Compiler::Options.new)
      iseq = RubyVM::InstructionSequence.compile(source, **options)
      iseq = InstructionSequence.from(iseq.to_a)
      iseq.specialize_instructions!
      VM.new.run_top_frame(iseq)
    end
  end
end
