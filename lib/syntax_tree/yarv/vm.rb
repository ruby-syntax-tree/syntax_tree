# frozen_string_literal: true

require "forwardable"

module SyntaxTree
  # This module provides an object representation of the YARV bytecode.
  module YARV
    class VM
      class Jump
        attr_reader :label

        def initialize(label)
          @label = label
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
        attr_accessor :line, :pc

        def initialize(iseq, parent, stack_index, _self, nesting)
          @iseq = iseq
          @parent = parent
          @stack_index = stack_index
          @_self = _self
          @nesting = nesting

          @svars = {}
          @line = iseq.line
          @pc = 0
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

        def initialize(iseq, nesting, parent, stack_index, _self, name, block)
          super(iseq, parent, stack_index, _self, nesting)
          @name = name
          @block = block
        end
      end

      class ClassFrame < Frame
        def initialize(iseq, parent, stack_index, _self)
          super(iseq, parent, stack_index, _self, parent.nesting + [_self])
        end
      end

      class RescueFrame < Frame
        def initialize(iseq, parent, stack_index)
          super(iseq, parent, stack_index, parent._self, parent.nesting)
        end
      end

      class ThrownError < StandardError
        attr_reader :value

        def initialize(value, backtrace)
          super("This error was thrown by the Ruby VM.")
          @value = value
          set_backtrace(backtrace)
        end
      end

      class ReturnError < ThrownError
      end

      class BreakError < ThrownError
      end

      class NextError < ThrownError
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
          nil
        end
      end

      # This is the main entrypoint for events firing in the VM, which allows
      # us to implement tracing.
      class NullEvents
        def publish_frame_change(frame)
        end

        def publish_instruction(iseq, insn)
        end

        def publish_stack_change(stack)
        end

        def publish_tracepoint(event)
        end
      end

      # This is a simple implementation of tracing that prints to STDOUT.
      class STDOUTEvents
        attr_reader :disassembler

        def initialize
          @disassembler = Disassembler.new
        end

        def publish_frame_change(frame)
          puts "%-16s %s" % ["frame-change", "#{frame.iseq.file}@#{frame.line}"]
        end

        def publish_instruction(iseq, insn)
          disassembler.current_iseq = iseq
          puts "%-16s %s" % ["instruction", insn.disasm(disassembler)]
        end

        def publish_stack_change(stack)
          puts "%-16s %s" % ["stack-change", stack.values.inspect]
        end

        def publish_tracepoint(event)
          puts "%-16s %s" % ["tracepoint", event.inspect]
        end
      end

      # This represents the global VM stack. It effectively is an array, but
      # wraps mutating functions with instrumentation.
      class Stack
        attr_reader :events, :values

        def initialize(events)
          @events = events
          @values = []
        end

        def concat(...)
          values.concat(...).tap { events.publish_stack_change(self) }
        end

        def last
          values.last
        end

        def length
          values.length
        end

        def push(...)
          values.push(...).tap { events.publish_stack_change(self) }
        end

        def pop(...)
          values.pop(...).tap { events.publish_stack_change(self) }
        end

        def slice!(...)
          values.slice!(...).tap { events.publish_stack_change(self) }
        end

        def [](...)
          values.[](...)
        end

        def []=(...)
          values.[]=(...).tap { events.publish_stack_change(self) }
        end
      end

      FROZEN_CORE = FrozenCore.new.freeze

      extend Forwardable

      attr_reader :events

      attr_reader :stack
      def_delegators :stack, :push, :pop

      attr_reader :frame

      def initialize(events = NullEvents.new)
        @events = events
        @stack = Stack.new(events)
        @frame = nil
      end

      def self.run(iseq)
        new.run_top_frame(iseq)
      end

      ##########################################################################
      # Helper methods for frames
      ##########################################################################

      def run_frame(frame)
        # First, set the current frame to the given value.
        previous = @frame
        @frame = frame
        events.publish_frame_change(@frame)

        # Next, set up the local table for the frame. This is actually incorrect
        # as it could use the values already on the stack, but for now we're
        # just doing this for simplicity.
        stack.concat(Array.new(frame.iseq.local_table.size))

        # Yield so that some frame-specific setup can be done.
        start_label = yield if block_given?
        frame.pc = frame.iseq.insns.index(start_label) if start_label

        # Finally we can execute the instructions one at a time. If they return
        # jumps or leaves we will handle those appropriately.
        loop do
          case (insn = frame.iseq.insns[frame.pc])
          when Integer
            frame.line = insn
            frame.pc += 1
          when Symbol
            events.publish_tracepoint(insn)
            frame.pc += 1
          when InstructionSequence::Label
            # skip labels
            frame.pc += 1
          else
            begin
              events.publish_instruction(frame.iseq, insn)
              result = insn.call(self)
            rescue ReturnError => error
              raise if frame.iseq.type != :method

              stack.slice!(frame.stack_index..)
              @frame = frame.parent
              events.publish_frame_change(@frame)

              return error.value
            rescue BreakError => error
              raise if frame.iseq.type != :block

              catch_entry =
                find_catch_entry(frame, InstructionSequence::CatchBreak)
              raise unless catch_entry

              stack.slice!(
                (
                  frame.stack_index + frame.iseq.local_table.size +
                    catch_entry.restore_sp
                )..
              )
              @frame = frame
              events.publish_frame_change(@frame)

              frame.pc = frame.iseq.insns.index(catch_entry.exit_label)
              push(result = error.value)
            rescue NextError => error
              raise if frame.iseq.type != :block

              catch_entry =
                find_catch_entry(frame, InstructionSequence::CatchNext)
              raise unless catch_entry

              stack.slice!(
                (
                  frame.stack_index + frame.iseq.local_table.size +
                    catch_entry.restore_sp
                )..
              )
              @frame = frame
              events.publish_frame_change(@frame)

              frame.pc = frame.iseq.insns.index(catch_entry.exit_label)
              push(result = error.value)
            rescue Exception => error
              catch_entry =
                find_catch_entry(frame, InstructionSequence::CatchRescue)
              raise unless catch_entry

              stack.slice!(
                (
                  frame.stack_index + frame.iseq.local_table.size +
                    catch_entry.restore_sp
                )..
              )
              @frame = frame
              events.publish_frame_change(@frame)

              frame.pc = frame.iseq.insns.index(catch_entry.exit_label)
              push(result = run_rescue_frame(catch_entry.iseq, frame, error))
            end

            case result
            when Jump
              frame.pc = frame.iseq.insns.index(result.label) + 1
            when Leave
              # this shouldn't be necessary, but is because we're not handling
              # the stack correctly at the moment
              stack.slice!(frame.stack_index..)

              # restore the previous frame
              @frame = previous || frame.parent
              events.publish_frame_change(@frame) if @frame

              return result.value
            else
              frame.pc += 1
            end
          end
        end
      end

      def find_catch_entry(frame, type)
        iseq = frame.iseq
        iseq.catch_table.find do |catch_entry|
          next unless catch_entry.is_a?(type)

          begin_pc = iseq.insns.index(catch_entry.begin_label)
          end_pc = iseq.insns.index(catch_entry.end_label)

          (begin_pc...end_pc).cover?(frame.pc)
        end
      end

      def run_top_frame(iseq)
        run_frame(TopFrame.new(iseq))
      end

      def run_block_frame(iseq, frame, *args, **kwargs, &block)
        run_frame(BlockFrame.new(iseq, frame, stack.length)) do
          setup_arguments(iseq, args, kwargs, block)
        end
      end

      def run_class_frame(iseq, clazz)
        run_frame(ClassFrame.new(iseq, frame, stack.length, clazz))
      end

      def run_method_frame(name, nesting, iseq, _self, *args, **kwargs, &block)
        run_frame(
          MethodFrame.new(
            iseq,
            nesting,
            frame,
            stack.length,
            _self,
            name,
            block
          )
        ) { setup_arguments(iseq, args, kwargs, block) }
      end

      def run_rescue_frame(iseq, frame, error)
        run_frame(RescueFrame.new(iseq, frame, stack.length)) do
          local_set(0, 0, error)
          nil
        end
      end

      def setup_arguments(iseq, args, kwargs, block)
        locals = [*args]
        local_index = 0
        start_label = nil

        # First, set up all of the leading arguments. These are positional and
        # required arguments at the start of the argument list.
        if (lead_num = iseq.argument_options[:lead_num])
          lead_num.times do
            local_set(local_index, 0, locals.shift)
            local_index += 1
          end
        end

        # Next, set up all of the optional arguments. The opt array contains
        # the labels that the frame should start at if the optional is
        # present. The last element of the array is the label that the frame
        # should start at if all of the optional arguments are present.
        if (opt = iseq.argument_options[:opt])
          opt[0...-1].each do |label|
            if locals.empty?
              start_label = label
              break
            else
              local_set(local_index, 0, locals.shift)
              local_index += 1
            end

            start_label = opt.last if start_label.nil?
          end
        end

        # If there is a splat argument, then we'll set that up here. It will
        # grab up all of the remaining positional arguments.
        if (rest_start = iseq.argument_options[:rest_start])
          if (post_start = iseq.argument_options[:post_start])
            length = post_start - rest_start
            local_set(local_index, 0, locals[0...length])
            locals = locals[length..]
          else
            local_set(local_index, 0, locals.dup)
            locals.clear
          end
          local_index += 1
        end

        # Next, set up any post arguments. These are positional arguments that
        # come after the splat argument.
        if (post_num = iseq.argument_options[:post_num])
          post_num.times do
            local_set(local_index, 0, locals.shift)
            local_index += 1
          end
        end

        if (keyword_option = iseq.argument_options[:keyword])
          # First, set up the keyword bits array.
          keyword_bits =
            keyword_option.map do |config|
              kwargs.key?(config.is_a?(Array) ? config[0] : config)
            end

          iseq.local_table.locals.each_with_index do |local, index|
            # If this is the keyword bits local, then set it appropriately.
            if local.name.is_a?(Integer)
              local_set(index, 0, keyword_bits)
              next
            end

            # First, find the configuration for this local in the keywords
            # list if it exists.
            name = local.name
            config =
              keyword_option.find do |keyword|
                keyword.is_a?(Array) ? keyword[0] == name : keyword == name
              end

            # If the configuration doesn't exist, then the local is not a
            # keyword local.
            next unless config

            if !config.is_a?(Array)
              # required keyword
              local_set(index, 0, kwargs.fetch(name))
            elsif !config[1].nil?
              # optional keyword with embedded default value
              local_set(index, 0, kwargs.fetch(name, config[1]))
            else
              # optional keyword with expression default value
              local_set(index, 0, kwargs[name])
            end
          end
        end

        local_set(local_index, 0, block) if iseq.argument_options[:block_start]

        start_label
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
        Jump.new(label)
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

      ##########################################################################
      # Methods for overriding runtime behavior
      ##########################################################################

      DLEXT = ".#{RbConfig::CONFIG["DLEXT"]}"
      SOEXT = ".#{RbConfig::CONFIG["SOEXT"]}"

      def require_resolved(filepath)
        $LOADED_FEATURES << filepath
        iseq = RubyVM::InstructionSequence.compile_file(filepath)
        run_top_frame(InstructionSequence.from(iseq.to_a))
      end

      def require_internal(filepath, loading: false)
        case (extname = File.extname(filepath))
        when ""
          # search for all the extensions
          searching = filepath
          extensions = ["", ".rb", DLEXT, SOEXT]
        when ".rb", DLEXT, SOEXT
          # search only for the given extension name
          searching = File.basename(filepath, extname)
          extensions = [extname]
        else
          # we don't handle these extensions, raise a load error
          raise LoadError, "cannot load such file -- #{filepath}"
        end

        if filepath.start_with?("/")
          # absolute path, search only in the given directory
          directories = [File.dirname(searching)]
          searching = File.basename(searching)
        else
          # relative path, search in the load path
          directories = $LOAD_PATH
        end

        directories.each do |directory|
          extensions.each do |extension|
            absolute_path = File.join(directory, "#{searching}#{extension}")
            next unless File.exist?(absolute_path)

            if !loading && $LOADED_FEATURES.include?(absolute_path)
              return false
            elsif extension == ".rb"
              require_resolved(absolute_path)
              return true
            elsif loading
              return Kernel.send(:yarv_load, filepath)
            else
              return Kernel.send(:yarv_require, filepath)
            end
          end
        end

        if loading
          Kernel.send(:yarv_load, filepath)
        else
          Kernel.send(:yarv_require, filepath)
        end
      end

      def require(filepath)
        require_internal(filepath, loading: false)
      end

      def require_relative(filepath)
        Kernel.yarv_require_relative(filepath)
      end

      def load(filepath)
        require_internal(filepath, loading: true)
      end

      def eval(
        source,
        binding = TOPLEVEL_BINDING,
        filename = "(eval)",
        lineno = 1
      )
        Kernel.yarv_eval(source, binding, filename, lineno)
      end

      def throw(tag, value = nil)
        Kernel.throw(tag, value)
      end

      def catch(tag, &block)
        Kernel.catch(tag, &block)
      end
    end
  end
end
