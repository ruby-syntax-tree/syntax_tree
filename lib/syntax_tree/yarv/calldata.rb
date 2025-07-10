# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This is an operand to various YARV instructions that represents the
    # information about a specific call site.
    class CallData
      flags = %i[
        CALL_ARGS_SPLAT
        CALL_ARGS_BLOCKARG
        CALL_FCALL
        CALL_VCALL
        CALL_ARGS_SIMPLE
        CALL_KWARG
        CALL_KW_SPLAT
        CALL_TAILCALL
        CALL_SUPER
        CALL_ZSUPER
        CALL_OPT_SEND
        CALL_KW_SPLAT_MUT
      ]

      # Insert the legacy CALL_BLOCKISEQ flag for Ruby 3.2 and earlier.
      flags.insert(5, :CALL_BLOCKISEQ) if RUBY_VERSION < "3.3"

      # Set the flags as constants on the class.
      flags.each_with_index { |name, index| const_set(name, 1 << index) }

      attr_reader :method, :argc, :flags, :kw_arg

      def initialize(
        method,
        argc = 0,
        flags = CallData::CALL_ARGS_SIMPLE,
        kw_arg = nil
      )
        @method = method
        @argc = argc
        @flags = flags
        @kw_arg = kw_arg
      end

      def flag?(mask)
        flags.anybits?(mask)
      end

      def to_h
        result = { mid: method, flag: flags, orig_argc: argc }
        result[:kw_arg] = kw_arg if kw_arg
        result
      end

      def inspect
        names = []
        names << :ARGS_SPLAT if flag?(CALL_ARGS_SPLAT)
        names << :ARGS_BLOCKARG if flag?(CALL_ARGS_BLOCKARG)
        names << :FCALL if flag?(CALL_FCALL)
        names << :VCALL if flag?(CALL_VCALL)
        names << :ARGS_SIMPLE if flag?(CALL_ARGS_SIMPLE)
        names << :KWARG if flag?(CALL_KWARG)
        names << :KW_SPLAT if flag?(CALL_KW_SPLAT)
        names << :TAILCALL if flag?(CALL_TAILCALL)
        names << :SUPER if flag?(CALL_SUPER)
        names << :ZSUPER if flag?(CALL_ZSUPER)
        names << :OPT_SEND if flag?(CALL_OPT_SEND)
        names << :KW_SPLAT_MUT if flag?(CALL_KW_SPLAT_MUT)

        parts = []
        parts << "mid:#{method}" if method
        parts << "argc:#{argc}"
        parts << "kw:[#{kw_arg.join(", ")}]" if kw_arg
        parts << names.join("|") if names.any?

        "<calldata!#{parts.join(", ")}>"
      end

      def self.from(serialized)
        new(
          serialized[:mid],
          serialized[:orig_argc],
          serialized[:flag],
          serialized[:kw_arg]
        )
      end
    end

    # A convenience method for creating a CallData object.
    def self.calldata(
      method,
      argc = 0,
      flags = CallData::CALL_ARGS_SIMPLE,
      kw_arg = nil
    )
      CallData.new(method, argc, flags, kw_arg)
    end
  end
end
