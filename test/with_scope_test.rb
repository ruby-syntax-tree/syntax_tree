# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class WithScopeTest < Minitest::Test
    class Collector < Visitor
      prepend WithScope

      attr_reader :arguments, :variables

      def initialize
        @arguments = {}
        @variables = {}
      end

      def self.collect(source)
        new.tap { SyntaxTree.parse(source).accept(_1) }
      end

      visit_methods do
        def visit_ident(node)
          value = node.value.delete_suffix(":")
          local = current_scope.find_local(node.value)

          case local&.type
          when :argument
            arguments[[current_scope.id, value]] = local
          when :variable
            variables[[current_scope.id, value]] = local
          end
        end

        def visit_label(node)
          value = node.value.delete_suffix(":")
          local = current_scope.find_local(value)

          if local&.type == :argument
            arguments[[current_scope.id, value]] = node
          end
        end

        def visit_vcall(node)
          local = current_scope.find_local(node.value)
          variables[[current_scope.id, value]] = local if local

          super
        end
      end
    end

    def test_collecting_simple_variables
      collector = Collector.collect(<<~RUBY)
        def foo
          a = 1
          a
        end
      RUBY

      assert_equal(1, collector.variables.length)
      assert_variable(collector, "a", definitions: [2], usages: [3])
    end

    def test_collecting_aref_variables
      collector = Collector.collect(<<~RUBY)
        def foo
          a = []
          a[1]
        end
      RUBY

      assert_equal(1, collector.variables.length)
      assert_variable(collector, "a", definitions: [2], usages: [3])
    end

    def test_collecting_multi_assign_variables
      collector = Collector.collect(<<~RUBY)
        def foo
          a, b = [1, 2]
          puts a
          puts b
        end
      RUBY

      assert_equal(2, collector.variables.length)
      assert_variable(collector, "a", definitions: [2], usages: [3])
      assert_variable(collector, "b", definitions: [2], usages: [4])
    end

    def test_collecting_pattern_matching_variables
      collector = Collector.collect(<<~RUBY)
        def foo
          case [1, 2]
          in Integer => a, Integer
            puts a
          end
        end
      RUBY

      # There are two occurrences, one on line 3 for pinning and one on line 4
      # for reference
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "a", definitions: [3], usages: [4])
    end

    def test_collecting_pinned_variables
      collector = Collector.collect(<<~RUBY)
        def foo
          a = 18
          case [1, 2]
          in ^a, *rest
            puts a
            puts rest
          end
        end
      RUBY

      assert_equal(2, collector.variables.length)
      assert_variable(collector, "a", definitions: [2], usages: [4, 5])
      assert_variable(collector, "rest", definitions: [4])

      # Rest is considered a vcall by the parser instead of a var_ref
      # assert_equal(1, variable_rest.usages.length)
      # assert_equal(6, variable_rest.usages[0].start_line)
    end

    if RUBY_VERSION >= "3.1"
      def test_collecting_one_line_pattern_matching_variables
        collector = Collector.collect(<<~RUBY)
          def foo
            [1] => a
            puts a
          end
        RUBY

        assert_equal(1, collector.variables.length)
        assert_variable(collector, "a", definitions: [2], usages: [3])
      end

      def test_collecting_endless_method_arguments
        collector = Collector.collect(<<~RUBY)
          def foo(a) = puts a
        RUBY

        assert_equal(1, collector.arguments.length)
        assert_argument(collector, "a", definitions: [1], usages: [1])
      end
    end

    def test_collecting_method_arguments
      collector = Collector.collect(<<~RUBY)
        def foo(a)
          puts a
        end
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "a", definitions: [1], usages: [2])
    end

    def test_collecting_singleton_method_arguments
      collector = Collector.collect(<<~RUBY)
        def self.foo(a)
          puts a
        end
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "a", definitions: [1], usages: [2])
    end

    def test_collecting_method_arguments_all_types
      collector = Collector.collect(<<~RUBY)
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

      assert_equal(7, collector.arguments.length)
      assert_argument(collector, "a", definitions: [1], usages: [2])
      assert_argument(collector, "b", definitions: [1], usages: [3])
      assert_argument(collector, "c", definitions: [1], usages: [4])
      assert_argument(collector, "d", definitions: [1], usages: [5])
      assert_argument(collector, "e", definitions: [1], usages: [6])
      assert_argument(collector, "f", definitions: [1], usages: [7])
      assert_argument(collector, "block", definitions: [1], usages: [8])
    end

    def test_collecting_block_arguments
      collector = Collector.collect(<<~RUBY)
        def foo
          [].each do |i|
            puts i
          end
        end
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "i", definitions: [2], usages: [3])
    end

    def test_collecting_one_line_block_arguments
      collector = Collector.collect(<<~RUBY)
        def foo
          [].each { |i| puts i }
        end
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "i", definitions: [2], usages: [2])
    end

    def test_collecting_shadowed_block_arguments
      collector = Collector.collect(<<~RUBY)
        def foo
          i = "something"

          [].each do |i|
            puts i
          end

          i
        end
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "i", definitions: [4], usages: [5])

      assert_equal(1, collector.variables.length)
      assert_variable(collector, "i", definitions: [2], usages: [8])
    end

    def test_collecting_shadowed_local_variables
      collector = Collector.collect(<<~RUBY)
        def foo(a)
          puts a
          a = 123
          a
        end
      RUBY

      # All occurrences are considered arguments, despite overriding the
      # argument value
      assert_equal(1, collector.arguments.length)
      assert_equal(0, collector.variables.length)
      assert_argument(collector, "a", definitions: [1, 3], usages: [2, 4])
    end

    def test_variables_in_the_top_level
      collector = Collector.collect(<<~RUBY)
        a = 123
        a
      RUBY

      assert_equal(0, collector.arguments.length)
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "a", definitions: [1], usages: [2])
    end

    def test_aref_field
      collector = Collector.collect(<<~RUBY)
        object = {}
        object["name"] = "something"
      RUBY

      assert_equal(0, collector.arguments.length)
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "object", definitions: [1], usages: [2])
    end

    def test_aref_on_a_method_call
      collector = Collector.collect(<<~RUBY)
        object = MyObject.new
        object.attributes["name"] = "something"
      RUBY

      assert_equal(0, collector.arguments.length)
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "object", definitions: [1], usages: [2])
    end

    def test_aref_with_two_accesses
      collector = Collector.collect(<<~RUBY)
        object = MyObject.new
        object["first"]["second"] ||= []
      RUBY

      assert_equal(0, collector.arguments.length)
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "object", definitions: [1], usages: [2])
    end

    def test_aref_on_a_method_call_with_arguments
      collector = Collector.collect(<<~RUBY)
        object = MyObject.new
        object.instance_variable_get(:@attributes)[:something] = :other_thing
      RUBY

      assert_equal(0, collector.arguments.length)
      assert_equal(1, collector.variables.length)
      assert_variable(collector, "object", definitions: [1], usages: [2])
    end

    def test_double_aref_on_method_call
      collector = Collector.collect(<<~RUBY)
        object = MyObject.new
        object["attributes"].find { |a| a["field"] == "expected" }["value"] = "changed"
      RUBY

      assert_equal(1, collector.arguments.length)
      assert_argument(collector, "a", definitions: [2], usages: [2])

      assert_equal(1, collector.variables.length)
      assert_variable(collector, "object", definitions: [1], usages: [2])
    end

    def test_nested_arguments
      collector = Collector.collect(<<~RUBY)
        [[1, [2, 3]]].each do |one, (two, three)|
          one
          two
          three
        end
      RUBY

      assert_equal(3, collector.arguments.length)
      assert_equal(0, collector.variables.length)

      assert_argument(collector, "one", definitions: [1], usages: [2])
      assert_argument(collector, "two", definitions: [1], usages: [3])
      assert_argument(collector, "three", definitions: [1], usages: [4])
    end

    def test_double_nested_arguments
      collector = Collector.collect(<<~RUBY)
        [[1, [2, 3]]].each do |one, (two, (three, four))|
          one
          two
          three
          four
        end
      RUBY

      assert_equal(4, collector.arguments.length)
      assert_equal(0, collector.variables.length)

      assert_argument(collector, "one", definitions: [1], usages: [2])
      assert_argument(collector, "two", definitions: [1], usages: [3])
      assert_argument(collector, "three", definitions: [1], usages: [4])
      assert_argument(collector, "four", definitions: [1], usages: [5])
    end

    def test_regex_named_capture_groups
      collector = Collector.collect(<<~RUBY)
        if /(?<one>\\w+)-(?<two>\\w+)/ =~ "something-else"
          one
          two
        end
      RUBY

      assert_equal(2, collector.variables.length)

      assert_variable(collector, "one", definitions: [1], usages: [2])
      assert_variable(collector, "two", definitions: [1], usages: [3])
    end

    def test_multiline_regex_named_capture_groups
      collector = Collector.collect(<<~RUBY)
        if %r{
          (?<one>\\w+)-
          (?<two>\\w+)
        } =~ "something-else"
          one
          two
        end
      RUBY

      assert_equal(2, collector.variables.length)

      assert_variable(collector, "one", definitions: [2], usages: [5])
      assert_variable(collector, "two", definitions: [3], usages: [6])
    end

    class Resolver < Visitor
      prepend WithScope

      attr_reader :locals

      def initialize
        @locals = []
      end

      visit_methods do
        def visit_assign(node)
          super.tap do
            level = 0
            name = node.target.value.value

            scope = current_scope
            while !scope.locals.key?(name) && !scope.parent.nil?
              level += 1
              scope = scope.parent
            end

            locals << [name, level]
          end
        end
      end
    end

    def test_resolver
      source = <<~RUBY
        module Level0
          level0 = 0

          class Level1
            level1 = 1

            def level2
              level2 = 2

              tap do |level3|
                level2 = 2
                level3 = 3

                tap do |level4|
                  level2 = 2
                  level4 = 4
                end
              end
            end
          end
        end
      RUBY

      resolver = Resolver.new
      SyntaxTree.parse(source).accept(resolver)

      expected = [
        ["level0", 0],
        ["level1", 0],
        ["level2", 0],
        ["level2", 1],
        ["level3", 0],
        ["level2", 2],
        ["level4", 0]
      ]

      assert_equal expected, resolver.locals
    end

    private

    def assert_collected(field, name, definitions: [], usages: [])
      keys = field.keys.select { |key| key[1] == name }
      assert_equal(1, keys.length)

      variable = field[keys.first]

      assert_equal(definitions.length, variable.definitions.length)
      definitions.each_with_index do |definition, index|
        assert_equal(definition, variable.definitions[index].start_line)
      end

      assert_equal(usages.length, variable.usages.length)
      usages.each_with_index do |usage, index|
        assert_equal(usage, variable.usages[index].start_line)
      end
    end

    def assert_argument(collector, name, definitions: [], usages: [])
      assert_collected(
        collector.arguments,
        name,
        definitions: definitions,
        usages: usages
      )
    end

    def assert_variable(collector, name, definitions: [], usages: [])
      assert_collected(
        collector.variables,
        name,
        definitions: definitions,
        usages: usages
      )
    end
  end
end
