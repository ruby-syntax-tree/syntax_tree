# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This is an operand to various YARV instructions that represents the
    # information about a specific call site.
    class CallData
      CALL_ARGS_SPLAT = 1 << 0
      CALL_ARGS_BLOCKARG = 1 << 1
      CALL_FCALL = 1 << 2
      CALL_VCALL = 1 << 3
      CALL_ARGS_SIMPLE = 1 << 4
      CALL_BLOCKISEQ = 1 << 5
      CALL_KWARG = 1 << 6
      CALL_KW_SPLAT = 1 << 7
      CALL_TAILCALL = 1 << 8
      CALL_SUPER = 1 << 9
      CALL_ZSUPER = 1 << 10
      CALL_OPT_SEND = 1 << 11
      CALL_KW_SPLAT_MUT = 1 << 12

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
        (flags & mask) > 0
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
        names << :BLOCKISEQ if flag?(CALL_BLOCKISEQ)
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
