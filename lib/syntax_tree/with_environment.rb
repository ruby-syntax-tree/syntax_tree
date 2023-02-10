# frozen_string_literal: true

module SyntaxTree
  # WithEnvironment is a module intended to be included in classes inheriting
  # from Visitor. The module overrides a few visit methods to automatically keep
  # track of local variables and arguments defined in the current environment.
  # Example usage:
  #   class MyVisitor < Visitor
  #     include WithEnvironment
  #
  #     def visit_ident(node)
  #       # Check if we're visiting an identifier for an argument, a local
  #       variable or something else
  #       local = current_environment.find_local(node)
  #
  #       if local.type == :argument
  #         # handle identifiers for arguments
  #       elsif local.type == :variable
  #         # handle identifiers for variables
  #       else
  #         # handle other identifiers, such as method names
  #       end
  #   end
  module WithEnvironment
    # The environment class is used to keep track of local variables and
    # arguments inside a particular scope
    class Environment
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

      # [Array[Local]] The local variables and arguments defined in this
      # environment
      attr_reader :locals

      # [Environment | nil] The parent environment
      attr_reader :parent

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

    def current_environment
      @current_environment ||= Environment.new
    end

    def with_new_environment
      previous_environment = @current_environment
      @current_environment = Environment.new(previous_environment)
      yield
    ensure
      @current_environment = previous_environment
    end

    # Visits for nodes that create new environments, such as classes, modules
    # and method definitions
    def visit_class(node)
      with_new_environment { super }
    end

    def visit_module(node)
      with_new_environment { super }
    end

    # When we find a method invocation with a block, only the code that happens
    # inside of the block needs a fresh environment. The method invocation
    # itself happens in the same environment
    def visit_method_add_block(node)
      visit(node.call)
      with_new_environment { visit(node.block) }
    end

    def visit_def(node)
      with_new_environment { super }
    end

    # Visit for keeping track of local arguments, such as method and block
    # arguments
    def visit_params(node)
      add_argument_definitions(node.requireds)

      node.posts.each do |param|
        current_environment.add_local_definition(param, :argument)
      end

      node.keywords.each do |param|
        current_environment.add_local_definition(param.first, :argument)
      end

      node.optionals.each do |param|
        current_environment.add_local_definition(param.first, :argument)
      end

      super
    end

    def visit_rest_param(node)
      name = node.name
      current_environment.add_local_definition(name, :argument) if name

      super
    end

    def visit_kwrest_param(node)
      name = node.name
      current_environment.add_local_definition(name, :argument) if name

      super
    end

    def visit_blockarg(node)
      name = node.name
      current_environment.add_local_definition(name, :argument) if name

      super
    end

    # Visit for keeping track of local variable definitions
    def visit_var_field(node)
      value = node.value

      if value.is_a?(SyntaxTree::Ident)
        current_environment.add_local_definition(value, :variable)
      end

      super
    end

    alias visit_pinned_var_ref visit_var_field

    # Visits for keeping track of variable and argument usages
    def visit_var_ref(node)
      value = node.value

      if value.is_a?(SyntaxTree::Ident)
        definition = current_environment.find_local(value.value)

        if definition
          current_environment.add_local_usage(value, definition.type)
        end
      end

      super
    end

    private

    def add_argument_definitions(list)
      list.each do |param|
        if param.is_a?(SyntaxTree::MLHSParen)
          add_argument_definitions(param.contents.parts)
        else
          current_environment.add_local_definition(param, :argument)
        end
      end
    end
  end
end
