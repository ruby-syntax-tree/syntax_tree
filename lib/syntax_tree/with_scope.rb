# frozen_string_literal: true

module SyntaxTree
  # WithScope is a module intended to be included in classes inheriting from
  # Visitor. The module overrides a few visit methods to automatically keep
  # track of local variables and arguments defined in the current scope.
  # Example usage:
  #
  #     class MyVisitor < Visitor
  #       include WithScope
  #
  #       def visit_ident(node)
  #         # Check if we're visiting an identifier for an argument, a local
  #         # variable or something else
  #         local = current_scope.find_local(node)
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
  module WithScope
    # The scope class is used to keep track of local variables and arguments
    # inside a particular scope.
    class Scope
      # This class tracks the occurrences of a local variable or argument.
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

      # [Integer] a unique identifier for this scope
      attr_reader :id

      # [scope | nil] The parent scope
      attr_reader :parent

      # [Hash[String, Local]] The local variables and arguments defined in this
      # scope
      attr_reader :locals

      def initialize(id, parent = nil)
        @id = id
        @parent = parent
        @locals = {}
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

      # Try to find the local given its name in this scope or any of its
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

    attr_reader :current_scope

    def initialize(*args, **kwargs, &block)
      super

      @current_scope = Scope.new(0)
      @next_scope_id = 0
    end

    # Visits for nodes that create new scopes, such as classes, modules
    # and method definitions.
    def visit_class(node)
      with_scope { super }
    end

    def visit_module(node)
      with_scope { super }
    end

    # When we find a method invocation with a block, only the code that happens
    # inside of the block needs a fresh scope. The method invocation
    # itself happens in the same scope.
    def visit_method_add_block(node)
      visit(node.call)
      with_scope(current_scope) { visit(node.block) }
    end

    def visit_def(node)
      with_scope { super }
    end

    # Visit for keeping track of local arguments, such as method and block
    # arguments.
    def visit_params(node)
      add_argument_definitions(node.requireds)
      add_argument_definitions(node.posts)

      node.keywords.each do |param|
        current_scope.add_local_definition(param.first, :argument)
      end

      node.optionals.each do |param|
        current_scope.add_local_definition(param.first, :argument)
      end

      super
    end

    def visit_rest_param(node)
      name = node.name
      current_scope.add_local_definition(name, :argument) if name

      super
    end

    def visit_kwrest_param(node)
      name = node.name
      current_scope.add_local_definition(name, :argument) if name

      super
    end

    def visit_blockarg(node)
      name = node.name
      current_scope.add_local_definition(name, :argument) if name

      super
    end

    def visit_block_var(node)
      node.locals.each do |local|
        current_scope.add_local_definition(local, :variable)
      end

      super
    end
    alias visit_lambda_var visit_block_var

    # Visit for keeping track of local variable definitions
    def visit_var_field(node)
      value = node.value
      current_scope.add_local_definition(value, :variable) if value.is_a?(Ident)

      super
    end

    # Visit for keeping track of local variable definitions
    def visit_pinned_var_ref(node)
      value = node.value
      current_scope.add_local_usage(value, :variable) if value.is_a?(Ident)

      super
    end

    # Visits for keeping track of variable and argument usages
    def visit_var_ref(node)
      value = node.value

      if value.is_a?(Ident)
        definition = current_scope.find_local(value.value)
        current_scope.add_local_usage(value, definition.type) if definition
      end

      super
    end

    # When using regex named capture groups, vcalls might actually be a variable
    def visit_vcall(node)
      value = node.value
      definition = current_scope.find_local(value.value)
      current_scope.add_local_usage(value, definition.type) if definition

      super
    end

    # Visit for capturing local variables defined in regex named capture groups
    def visit_binary(node)
      if node.operator == :=~
        left = node.left

        if left.is_a?(RegexpLiteral) && left.parts.length == 1 &&
             left.parts.first.is_a?(TStringContent)
          content = left.parts.first

          value = content.value
          location = content.location
          start_line = location.start_line

          Regexp
            .new(value, Regexp::FIXEDENCODING)
            .names
            .each do |name|
              offset = value.index(/\(\?<#{Regexp.escape(name)}>/)
              line = start_line + value[0...offset].count("\n")

              # We need to add 3 to account for these three characters
              # prefixing a named capture (?<
              column = location.start_column + offset + 3
              if value[0...offset].include?("\n")
                column =
                  value[0...offset].length - value[0...offset].rindex("\n") +
                    3 - 1
              end

              ident_location =
                Location.new(
                  start_line: line,
                  start_char: location.start_char + offset,
                  start_column: column,
                  end_line: line,
                  end_char: location.start_char + offset + name.length,
                  end_column: column + name.length
                )

              identifier = Ident.new(value: name, location: ident_location)
              current_scope.add_local_definition(identifier, :variable)
            end
        end
      end

      super
    end

    private

    def add_argument_definitions(list)
      list.each do |param|
        case param
        when ArgStar
          value = param.value
          current_scope.add_local_definition(value, :argument) if value
        when MLHSParen
          add_argument_definitions(param.contents.parts)
        else
          current_scope.add_local_definition(param, :argument)
        end
      end
    end

    def next_scope_id
      @next_scope_id += 1
    end

    def with_scope(parent_scope = nil)
      previous_scope = @current_scope
      @current_scope = Scope.new(next_scope_id, parent_scope)
      yield
    ensure
      @current_scope = previous_scope
    end
  end
end
