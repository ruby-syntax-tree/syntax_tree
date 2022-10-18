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

    def visit_defs(node)
      with_new_environment { super }
    end

    def visit_def_endless(node)
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
