# frozen_string_literal: true

module SyntaxTree
  # WithEnvironment is a module intended to be included in classes inheriting
  # from Visitor. The module overrides a few visit methods to automatically keep
  # track of local variables and arguments defined in the current environment.
  # Example usage:
  #
  #     class MyVisitor < Visitor
  #       include WithEnvironment
  #
  #       def visit_ident(node)
  #         # Check if we're visiting an identifier for an argument, a local
  #         # variable or something else
  #         local = current_environment.find_local(node)
  #
  #         if local.type == :argument
  #           # handle identifiers for arguments
  #         elsif local.type == :variable
  #           # handle identifiers for variables
  #         else
  #           # handle other identifiers, such as method names
  #         end
  #       end
  #     end
  #
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

        def initialize(type)
          @type = type
          @definitions = []
          @usages = []
        end

        def add_definition(location)
          @definitions << location
        end

        def add_usage(location)
          @usages << location
        end
      end

      # [Integer] a unique identifier for this environment
      attr_reader :id

      # [Hash[String, Local]] The local variables and arguments defined in this
      # environment
      attr_reader :locals

      # [Environment | nil] The parent environment
      attr_reader :parent

      def initialize(id, parent = nil)
        @id = id
        @locals = {}
        @parent = parent
      end

      # Adding a local definition will either insert a new entry in the locals
      # hash or append a new definition location to an existing local. Notice
      # that it's not possible to change the type of a local after it has been
      # registered.
      def add_local_definition(identifier, type)
        name = identifier.value.delete_suffix(":")

        local =
          if type == :argument
            locals[name] ||= Local.new(type)
          else
            resolve_local(name, type)
          end

        local.add_definition(identifier.location)
      end

      # Adding a local usage will either insert a new entry in the locals
      # hash or append a new usage location to an existing local. Notice that
      # it's not possible to change the type of a local after it has been
      # registered.
      def add_local_usage(identifier, type)
        name = identifier.value.delete_suffix(":")
        resolve_local(name, type).add_usage(identifier.location)
      end

      # Try to find the local given its name in this environment or any of its
      # parents.
      def find_local(name)
        locals[name] || parent&.find_local(name)
      end

      private

      def resolve_local(name, type)
        local = find_local(name)

        unless local
          local = Local.new(type)
          locals[name] = local
        end

        local
      end
    end

    def initialize(*args, **kwargs, &block)
      super
      @environment_id = 0
    end

    def current_environment
      @current_environment ||= Environment.new(next_environment_id)
    end

    def with_new_environment(parent_environment = nil)
      previous_environment = @current_environment
      @current_environment =
        Environment.new(next_environment_id, parent_environment)
      yield
    ensure
      @current_environment = previous_environment
    end

    # Visits for nodes that create new environments, such as classes, modules
    # and method definitions.
    def visit_class(node)
      with_new_environment { super }
    end

    def visit_module(node)
      with_new_environment { super }
    end

    # When we find a method invocation with a block, only the code that
    # happens inside of the block needs a fresh environment. The method
    # invocation itself happens in the same environment.
    def visit_method_add_block(node)
      visit(node.call)
      with_new_environment(current_environment) { visit(node.block) }
    end

    def visit_def(node)
      with_new_environment { super }
    end

    # Visit for keeping track of local arguments, such as method and block
    # arguments.
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

    def next_environment_id
      @environment_id += 1
    end
  end
end