# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class VisitorWithEnvironmentTest < Minitest::Test
    class Collector < Visitor
      include WithEnvironment

      attr_reader :variables, :arguments

      def initialize
        @variables = {}
        @arguments = {}
      end

      visit_methods do
        def visit_ident(node)
          local = current_environment.find_local(node.value)
          return unless local

          value = node.value.delete_suffix(":")

          case local.type
          when :argument
            @arguments[value] = local
          when :variable
            @variables[value] = local
          end
        end

        def visit_label(node)
          value = node.value.delete_suffix(":")
          local = current_environment.find_local(value)
          return unless local

          @arguments[value] = node if local.type == :argument
        end
      end
    end

    def test_collecting_simple_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          a = 1
          a
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["a"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(2, variable.definitions[0].start_line)
      assert_equal(3, variable.usages[0].start_line)
    end

    def test_collecting_aref_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          a = []
          a[1]
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["a"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(2, variable.definitions[0].start_line)
      assert_equal(3, variable.usages[0].start_line)
    end

    def test_collecting_multi_assign_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          a, b = [1, 2]
          puts a
          puts b
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(2, visitor.variables.length)

      variable_a = visitor.variables["a"]
      assert_equal(1, variable_a.definitions.length)
      assert_equal(1, variable_a.usages.length)

      assert_equal(2, variable_a.definitions[0].start_line)
      assert_equal(3, variable_a.usages[0].start_line)

      variable_b = visitor.variables["b"]
      assert_equal(1, variable_b.definitions.length)
      assert_equal(1, variable_b.usages.length)

      assert_equal(2, variable_b.definitions[0].start_line)
      assert_equal(4, variable_b.usages[0].start_line)
    end

    def test_collecting_pattern_matching_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          case [1, 2]
          in Integer => a, Integer
            puts a
          end
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      # There are two occurrences, one on line 3 for pinning and one on line 4
      # for reference
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["a"]

      # Assignment a
      assert_equal(3, variable.definitions[0].start_line)
      assert_equal(4, variable.usages[0].start_line)
    end

    def test_collecting_pinned_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          a = 18
          case [1, 2]
          in ^a, *rest
            puts a
            puts rest
          end
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(2, visitor.variables.length)

      variable_a = visitor.variables["a"]
      assert_equal(2, variable_a.definitions.length)
      assert_equal(1, variable_a.usages.length)

      assert_equal(2, variable_a.definitions[0].start_line)
      assert_equal(4, variable_a.definitions[1].start_line)
      assert_equal(5, variable_a.usages[0].start_line)

      variable_rest = visitor.variables["rest"]
      assert_equal(1, variable_rest.definitions.length)
      assert_equal(4, variable_rest.definitions[0].start_line)

      # Rest is considered a vcall by the parser instead of a var_ref
      # assert_equal(1, variable_rest.usages.length)
      # assert_equal(6, variable_rest.usages[0].start_line)
    end

    if RUBY_VERSION >= "3.1"
      def test_collecting_one_line_pattern_matching_variables
        tree = SyntaxTree.parse(<<~RUBY)
          def foo
            [1] => a
            puts a
          end
        RUBY

        visitor = Collector.new
        visitor.visit(tree)

        assert_equal(1, visitor.variables.length)

        variable = visitor.variables["a"]
        assert_equal(1, variable.definitions.length)
        assert_equal(1, variable.usages.length)

        assert_equal(2, variable.definitions[0].start_line)
        assert_equal(3, variable.usages[0].start_line)
      end

      def test_collecting_endless_method_arguments
        tree = SyntaxTree.parse(<<~RUBY)
          def foo(a) = puts a
        RUBY

        visitor = Collector.new
        visitor.visit(tree)

        assert_equal(1, visitor.arguments.length)

        argument = visitor.arguments["a"]
        assert_equal(1, argument.definitions.length)
        assert_equal(1, argument.usages.length)

        assert_equal(1, argument.definitions[0].start_line)
        assert_equal(1, argument.usages[0].start_line)
      end
    end

    def test_collecting_method_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        def foo(a)
          puts a
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)

      argument = visitor.arguments["a"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)
    end

    def test_collecting_singleton_method_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        def self.foo(a)
          puts a
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)

      argument = visitor.arguments["a"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)
    end

    def test_collecting_method_arguments_all_types
      tree = SyntaxTree.parse(<<~RUBY)
        def foo(a, b = 1, *c, d, e: 1, **f, &block)
          puts a
          puts b
          puts c
          puts d
          puts e
          puts f
          block.call
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(7, visitor.arguments.length)

      argument_a = visitor.arguments["a"]
      assert_equal(1, argument_a.definitions.length)
      assert_equal(1, argument_a.usages.length)
      assert_equal(1, argument_a.definitions[0].start_line)
      assert_equal(2, argument_a.usages[0].start_line)

      argument_b = visitor.arguments["b"]
      assert_equal(1, argument_b.definitions.length)
      assert_equal(1, argument_b.usages.length)
      assert_equal(1, argument_b.definitions[0].start_line)
      assert_equal(3, argument_b.usages[0].start_line)

      argument_c = visitor.arguments["c"]
      assert_equal(1, argument_c.definitions.length)
      assert_equal(1, argument_c.usages.length)
      assert_equal(1, argument_c.definitions[0].start_line)
      assert_equal(4, argument_c.usages[0].start_line)

      argument_d = visitor.arguments["d"]
      assert_equal(1, argument_d.definitions.length)
      assert_equal(1, argument_d.usages.length)
      assert_equal(1, argument_d.definitions[0].start_line)
      assert_equal(5, argument_d.usages[0].start_line)

      argument_e = visitor.arguments["e"]
      assert_equal(1, argument_e.definitions.length)
      assert_equal(1, argument_e.usages.length)
      assert_equal(1, argument_e.definitions[0].start_line)
      assert_equal(6, argument_e.usages[0].start_line)

      argument_f = visitor.arguments["f"]
      assert_equal(1, argument_f.definitions.length)
      assert_equal(1, argument_f.usages.length)
      assert_equal(1, argument_f.definitions[0].start_line)
      assert_equal(7, argument_f.usages[0].start_line)

      argument_block = visitor.arguments["block"]
      assert_equal(1, argument_block.definitions.length)
      assert_equal(1, argument_block.usages.length)
      assert_equal(1, argument_block.definitions[0].start_line)
      assert_equal(8, argument_block.usages[0].start_line)
    end

    def test_collecting_block_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          [].each do |i|
            puts i
          end
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)

      argument = visitor.arguments["i"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)
      assert_equal(2, argument.definitions[0].start_line)
      assert_equal(3, argument.usages[0].start_line)
    end

    def test_collecting_one_line_block_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          [].each { |i| puts i }
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)

      argument = visitor.arguments["i"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)
      assert_equal(2, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)
    end

    def test_collecting_shadowed_block_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        def foo
          i = "something"

          [].each do |i|
            puts i
          end

          i
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      argument = visitor.arguments["i"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)
      assert_equal(4, argument.definitions[0].start_line)
      assert_equal(5, argument.usages[0].start_line)

      variable = visitor.variables["i"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)
      assert_equal(2, variable.definitions[0].start_line)
      assert_equal(8, variable.usages[0].start_line)
    end

    def test_collecting_shadowed_local_variables
      tree = SyntaxTree.parse(<<~RUBY)
        def foo(a)
          puts a
          a = 123
          a
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      # All occurrences are considered arguments, despite overriding the
      # argument value
      assert_equal(1, visitor.arguments.length)
      assert_equal(0, visitor.variables.length)

      argument = visitor.arguments["a"]
      assert_equal(2, argument.definitions.length)
      assert_equal(2, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(3, argument.definitions[1].start_line)
      assert_equal(2, argument.usages[0].start_line)
      assert_equal(4, argument.usages[1].start_line)
    end

    def test_variables_in_the_top_level
      tree = SyntaxTree.parse(<<~RUBY)
        a = 123
        a
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(0, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["a"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)
    end

    def test_aref_field
      tree = SyntaxTree.parse(<<~RUBY)
        object = {}
        object["name"] = "something"
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(0, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["object"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)
    end

    def test_aref_on_a_method_call
      tree = SyntaxTree.parse(<<~RUBY)
        object = MyObject.new
        object.attributes["name"] = "something"
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(0, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["object"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)
    end

    def test_aref_with_two_accesses
      tree = SyntaxTree.parse(<<~RUBY)
        object = MyObject.new
        object["first"]["second"] ||= []
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(0, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["object"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)
    end

    def test_aref_on_a_method_call_with_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        object = MyObject.new
        object.instance_variable_get(:@attributes)[:something] = :other_thing
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(0, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["object"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)
    end

    def test_double_aref_on_method_call
      tree = SyntaxTree.parse(<<~RUBY)
        object = MyObject.new
        object["attributes"].find { |a| a["field"] == "expected" }["value"] = "changed"
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(1, visitor.arguments.length)
      assert_equal(1, visitor.variables.length)

      variable = visitor.variables["object"]
      assert_equal(1, variable.definitions.length)
      assert_equal(1, variable.usages.length)

      assert_equal(1, variable.definitions[0].start_line)
      assert_equal(2, variable.usages[0].start_line)

      argument = visitor.arguments["a"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(2, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)
    end

    def test_nested_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        [[1, [2, 3]]].each do |one, (two, three)|
          one
          two
          three
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(3, visitor.arguments.length)
      assert_equal(0, visitor.variables.length)

      argument = visitor.arguments["one"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)

      argument = visitor.arguments["two"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(3, argument.usages[0].start_line)

      argument = visitor.arguments["three"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(4, argument.usages[0].start_line)
    end

    def test_double_nested_arguments
      tree = SyntaxTree.parse(<<~RUBY)
        [[1, [2, 3]]].each do |one, (two, (three, four))|
          one
          two
          three
          four
        end
      RUBY

      visitor = Collector.new
      visitor.visit(tree)

      assert_equal(4, visitor.arguments.length)
      assert_equal(0, visitor.variables.length)

      argument = visitor.arguments["one"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(2, argument.usages[0].start_line)

      argument = visitor.arguments["two"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(3, argument.usages[0].start_line)

      argument = visitor.arguments["three"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(4, argument.usages[0].start_line)

      argument = visitor.arguments["four"]
      assert_equal(1, argument.definitions.length)
      assert_equal(1, argument.usages.length)

      assert_equal(1, argument.definitions[0].start_line)
      assert_equal(5, argument.usages[0].start_line)
    end

    class Resolver < Visitor
      include WithEnvironment

      attr_reader :locals

      def initialize
        @locals = []
      end

      visit_methods do
        def visit_assign(node)
          level = 0
          environment = current_environment
          level += 1 until (environment = environment.parent).nil?

          locals << [node.target.value.value, level]
          super
        end
      end
    end

    def test_class
      source = <<~RUBY
        module Level0
          level0 = 0

          module Level1
            level1 = 1

            class Level2
              level2 = 2
            end
          end
        end
      RUBY

      visitor = Resolver.new
      SyntaxTree.parse(source).accept(visitor)

      assert_equal [["level0", 0], ["level1", 1], ["level2", 2]], visitor.locals
    end
  end
end
