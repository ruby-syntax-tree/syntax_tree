# frozen_string_literal: true

module SyntaxTree
  # The environment class is used to keep track of local variables and arguments
  # inside a particular scope
  class Environment
    # [Array[Local]] The local variables and arguments defined in this
    # environment
    attr_reader :locals

    # This class tracks the occurrences of a local variable or argument
    class Local
      # [Symbol] The type of the local (e.g. :argument, :variable)
      attr_reader :type

      # [Array[Location]] The locations of all definitions and assignments of
      # this local
      attr_reader :definitions

      # [Array[Location]] The locations of all usages of this local
      attr_reader :usages

      #   initialize: (Symbol type) -> void
      def initialize(type)
        @type = type
        @definitions = []
        @usages = []
      end

      #   add_definition: (Location location) -> void
      def add_definition(location)
        @definitions << location
      end

      #   add_usage: (Location location) -> void
      def add_usage(location)
        @usages << location
      end
    end

    #   initialize: (Environment | nil parent) -> void
    def initialize(parent = nil)
      @locals = {}
      @parent = parent
    end

    # Adding a local definition will either insert a new entry in the locals
    # hash or append a new definition location to an existing local. Notice that
    # it's not possible to change the type of a local after it has been
    # registered
    #   add_local_definition: (Ident | Label identifier, Symbol type) -> void
    def add_local_definition(identifier, type)
      name = identifier.value.delete_suffix(":")

      @locals[name] ||= Local.new(type)
      @locals[name].add_definition(identifier.location)
    end

    # Adding a local usage will either insert a new entry in the locals
    # hash or append a new usage location to an existing local. Notice that
    # it's not possible to change the type of a local after it has been
    # registered
    #   add_local_usage: (Ident | Label identifier, Symbol type) -> void
    def add_local_usage(identifier, type)
      name = identifier.value.delete_suffix(":")

      @locals[name] ||= Local.new(type)
      @locals[name].add_usage(identifier.location)
    end

    # Try to find the local given its name in this environment or any of its
    # parents
    #   find_local: (String name) -> Local | nil
    def find_local(name)
      local = @locals[name]
      return local unless local.nil?

      @parent&.find_local(name)
    end
  end
end
