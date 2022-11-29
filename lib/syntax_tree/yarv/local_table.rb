# frozen_string_literal: true

module SyntaxTree
  module YARV
    # This represents every local variable associated with an instruction
    # sequence. There are two kinds of locals: plain locals that are what you
    # expect, and block proxy locals, which represent local variables
    # associated with blocks that were passed into the current instruction
    # sequence.
    class LocalTable
      # A local representing a block passed into the current instruction
      # sequence.
      class BlockLocal
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      # A regular local variable.
      class PlainLocal
        attr_reader :name

        def initialize(name)
          @name = name
        end
      end

      # The result of looking up a local variable in the current local table.
      class Lookup
        attr_reader :local, :index, :level

        def initialize(local, index, level)
          @local = local
          @index = index
          @level = level
        end
      end

      attr_reader :locals

      def initialize
        @locals = []
      end

      def empty?
        locals.empty?
      end

      def find(name, level = 0)
        index = locals.index { |local| local.name == name }
        Lookup.new(locals[index], index, level) if index
      end

      def has?(name)
        locals.any? { |local| local.name == name }
      end

      def names
        locals.map(&:name)
      end

      def name_at(index)
        locals[index].name
      end

      def size
        locals.length
      end

      # Add a BlockLocal to the local table.
      def block(name)
        locals << BlockLocal.new(name) unless has?(name)
      end

      # Add a PlainLocal to the local table.
      def plain(name)
        locals << PlainLocal.new(name) unless has?(name)
      end

      # This is the offset from the top of the stack where this local variable
      # lives.
      def offset(index)
        size - (index - 3) - 1
      end
    end
  end
end
