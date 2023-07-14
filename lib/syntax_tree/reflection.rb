# frozen_string_literal: true

module SyntaxTree
  # This module is used to provide some reflection on the various types of nodes
  # and their attributes. As soon as it is required it collects all of its
  # information.
  module Reflection
    # This module represents the type of the values being passed to attributes
    # of nodes. It is used as part of the documentation of the attributes.
    module Type
      CONSTANTS = SyntaxTree.constants.to_h { [_1, SyntaxTree.const_get(_1)] }

      # Represents an array type that holds another type.
      class ArrayType
        attr_reader :type

        def initialize(type)
          @type = type
        end

        def ===(value)
          value.is_a?(Array) && value.all? { type === _1 }
        end

        def inspect
          "Array<#{type.inspect}>"
        end
      end

      # Represents a tuple type that holds a number of types in order.
      class TupleType
        attr_reader :types

        def initialize(types)
          @types = types
        end

        def ===(value)
          value.is_a?(Array) && value.length == types.length &&
            value.zip(types).all? { |item, type| type === item }
        end

        def inspect
          "[#{types.map(&:inspect).join(", ")}]"
        end
      end

      # Represents a union type that can be one of a number of types.
      class UnionType
        attr_reader :types

        def initialize(types)
          @types = types
        end

        def ===(value)
          types.any? { _1 === value }
        end

        def inspect
          types.map(&:inspect).join(" | ")
        end
      end

      class << self
        def parse(comment)
          comment = comment.gsub("\n", " ")

          unless comment.start_with?("[")
            raise "Comment does not start with a bracket: #{comment.inspect}"
          end

          count = 1
          found =
            comment.chars[1..]
              .find
              .with_index(1) do |char, index|
                count += { "[" => 1, "]" => -1 }.fetch(char, 0)
                break index if count == 0
              end

          # If we weren't able to find the end of the balanced brackets, then
          # the comment is malformed.
          if found.nil?
            raise "Comment does not have balanced brackets: #{comment.inspect}"
          end

          parse_type(comment[1...found].strip)
        end

        private

        def parse_type(value)
          case value
          when "Integer"
            Integer
          when "String"
            String
          when "Symbol"
            Symbol
          when "boolean"
            UnionType.new([TrueClass, FalseClass])
          when "nil"
            NilClass
          when ":\"::\""
            :"::"
          when ":call"
            :call
          when ":nil"
            :nil
          when /\AArray\[(.+)\]\z/
            ArrayType.new(parse_type($1.strip))
          when /\A\[(.+)\]\z/
            TupleType.new($1.strip.split(/\s*,\s*/).map { parse_type(_1) })
          else
            if value.include?("|")
              UnionType.new(value.split(/\s*\|\s*/).map { parse_type(_1) })
            else
              CONSTANTS.fetch(value.to_sym)
            end
          end
        end
      end
    end

    # This class represents one of the attributes on a node in the tree.
    class Attribute
      attr_reader :name, :comment, :type

      def initialize(name, comment)
        @name = name
        @comment = comment
        @type = Type.parse(comment)
      end
    end

    # This class represents one of our nodes in the tree. We're going to use it
    # as a placeholder for collecting all of the various places that nodes are
    # used.
    class Node
      attr_reader :name, :comment, :attributes, :visitor_method

      def initialize(name, comment, attributes, visitor_method)
        @name = name
        @comment = comment
        @attributes = attributes
        @visitor_method = visitor_method
      end
    end

    class << self
      # This is going to hold a hash of all of the nodes in the tree. The keys
      # are the names of the nodes as symbols.
      attr_reader :nodes

      # This expects a node name as a symbol and returns the node object for
      # that node.
      def node(name)
        nodes.fetch(name)
      end

      private

      def parse_comments(statements, index)
        statements[0...index]
          .reverse_each
          .take_while { _1.is_a?(SyntaxTree::Comment) }
          .reverse_each
          .map { _1.value[2..] }
      end
    end

    @nodes = {}

    # For each node, we're going to parse out its attributes and other metadata.
    # We'll use this as the basis for our report.
    program =
      SyntaxTree.parse(SyntaxTree.read(File.expand_path("node.rb", __dir__)))

    program_statements = program.statements
    main_statements = program_statements.body.last.bodystmt.statements.body
    main_statements.each_with_index do |main_statement, main_statement_index|
      # Ensure we are only looking at class declarations.
      next unless main_statement.is_a?(SyntaxTree::ClassDeclaration)

      # Ensure we're looking at class declarations with superclasses.
      superclass = main_statement.superclass
      next unless superclass.is_a?(SyntaxTree::VarRef)

      # Ensure we're looking at class declarations that inherit from Node.
      next unless superclass.value.value == "Node"

      # All child nodes inherit the location attr_reader from Node, so we'll add
      # that to the list of attributes first.
      attributes = {
        location:
          Attribute.new(:location, "[Location] the location of this node")
      }

      # This is the name of the method tha gets called on the given visitor when
      # the accept method is called on this node.
      visitor_method = nil

      statements = main_statement.bodystmt.statements.body
      statements.each_with_index do |statement, statement_index|
        case statement
        when SyntaxTree::Command
          # We only use commands in node classes to define attributes. So, we
          # can safely assume that we're looking at an attribute definition.
          unless %w[attr_reader attr_accessor].include?(statement.message.value)
            raise "Unexpected command: #{statement.message.value.inspect}"
          end

          # The arguments to the command are the attributes that we're defining.
          # We want to ensure that we're only defining one at a time.
          if statement.arguments.parts.length != 1
            raise "Declaring more than one attribute at a time is not permitted"
          end

          attribute =
            Attribute.new(
              statement.arguments.parts.first.value.value.to_sym,
              "#{parse_comments(statements, statement_index).join("\n")}\n"
            )

          # Ensure that we don't already have an attribute named the same as
          # this one, and then add it to the list of attributes.
          if attributes.key?(attribute.name)
            raise "Duplicate attribute: #{attribute.name}"
          end

          attributes[attribute.name] = attribute
        when SyntaxTree::DefNode
          if statement.name.value == "accept"
            call_node = statement.bodystmt.statements.body.first
            visitor_method = call_node.message.value.to_sym
          end
        end
      end

      # If we never found a visitor method, then we have an error.
      raise if visitor_method.nil?

      # Finally, set it up in the hash of nodes so that we can use it later.
      comments = parse_comments(main_statements, main_statement_index)
      node =
        Node.new(
          main_statement.constant.constant.value.to_sym,
          "#{comments.join("\n")}\n",
          attributes,
          visitor_method
        )

      @nodes[node.name] = node
    end
  end
end
