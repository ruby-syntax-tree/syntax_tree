# frozen_string_literal: true

module YARP
  module FlowControlNode
    def format(q)
      # If there are no arguments associated with this flow control, then we can
      # safely just print the keyword and return.
      if arguments.nil?
        q.slice(keyword_loc)
        return
      end

      # If there are multiple arguments associated with this flow control, then
      # we're going to print the keyword and then print the arguments surrounded
      # by brackets if they split onto multiple lines.
      if arguments.arguments.length > 1
        format_arguments(q, " [", "]")
        return
      end

      # Otherwise, we're formatting a single argument. We'll do different
      # formatting based on the type of the argument.
      q.group do
        q.slice(keyword_loc)

        case (argument = arguments.arguments.first)
        when ParenthesesNode
          statements = argument.statements.body

          if statements.length == 1
            statement = statements.first

            if statement.is_a?(ArrayNode)
              elements = statement.elements

              if elements.length >= 2
                # Here we have a single argument that is a set of parentheses
                # wrapping an array literal that has at least 2 elements.
                # We're going to print the contents of the array directly.
                # This would be like if we had:
                #
                #     break([1, 2, 3])
                #
                # which we will print as:
                #
                #     break 1, 2, 3
                #
                q.text(" ")
                format_array_contents(q, statement)
              else
                # Here we have a single argument that is a set of parentheses
                # wrapping an array literal that has 0 or 1 elements. We're
                # going to skip the parentheses but print the array itself.
                # This would be like if we had:
                #
                #     break([1])
                #
                # which we will print as:
                #
                #     break [1]
                #
                q.text(" ")
                q.format(statement)
              end
            elsif skip_parens?(statement)
              # Here we have a single argument that is a set of parentheses
              # that themselves contain a single statement. That statement is
              # a simple value that we can skip the parentheses for. This
              # would be like if we had:
              #
              #     break(1)
              #
              # which we will print as:
              #
              #     break 1
              #
              q.text(" ")
              q.format(statement)
            else
              # Here we have a single argument that is a set of parentheses.
              # We're going to print the parentheses themselves as if they
              # were the set of arguments. This would be like if we had:
              #
              #     break(foo.bar)
              #
              q.format(argument)
            end
          else
            q.format(argument)
          end
        when ArrayNode
          elements = argument.elements

          if elements.length >= 2
            # Here there is a single argument that is an array literal with at
            # least two elements. We skip directly into the array literal's
            # elements in order to print the contents. This would be like if
            # we had:
            #
            #     break [1, 2, 3]
            #
            # which we will print as:
            #
            #     break 1, 2, 3
            #
            q.text(" ")
            format_array_contents(q, argument)
          else
            # Here there is a single argument that is an array literal with 0
            # or 1 elements. In this case we're going to print the array as it
            # is because skipping the brackets would change the remaining.
            # This would be like if we had:
            #
            #     break []
            #     break [1]
            #
            q.text(" ")
            q.format(argument)
          end
        else
          # Here there is a single argument that hasn't matched one of our
          # previous cases. We're going to print the argument as it is. This
          # would be like if we had:
          #
          #     break foo
          #
          format_arguments(q, "(", ")")
        end
      end
    end

    private

    def format_array_contents(q, array)
      q.if_break { q.text("[") }
      q.indent do
        q.breakable_empty
        q.seplist(array.elements) { |element| q.format(element) }
      end
      q.breakable_empty
      q.if_break { q.text("]") }
    end

    def format_arguments(q, opening, closing)
      q.if_break { q.text(opening) }
      q.indent do
        q.breakable_space
        q.format(arguments)
      end
      q.breakable_empty
      q.if_break { q.text(closing) }
    end

    def skip_parens?(node)
      case node
      when BackReferenceReadNode, ClassVariableReadNode, FloatNode,
           GlobalVariableReadNode, ImaginaryNode, InstanceVariableReadNode,
           IntegerNode, RationalNode, SelfNode
        true
      else
        false
      end
    end
  end

  # This module is responsible for formatting the elements contained within a
  # hash or keyword hash. It first determines if every key in the hash can use
  # labels. If it can, it uses labels. Otherwise it uses hash rockets.
  module HashKeyFormatter
    # Formats the keys of a hash literal using labels.
    class Labels
      LABEL = /\A[A-Za-z_](\w*[\w!?])?\z/.freeze

      def format_key(q, key)
        case key
        when SymbolNode
        when InterpolatedSymbolNode
          
        else
          raise "Unexpected key: #{key}"
        end

        if key.is_a?(SymbolNode) && key.opening_loc.nil? && !key.closing_loc.nil?
          q.format(key)
        elsif key.is_a?(SymbolNode)
          # When attempting to convert a hash rocket into a hash label,
          # you need to take care because only certain patterns are
          # allowed.
          q.text(key.unescaped)
          q.text(":")
        else
          binding.irb
        end


        # case key
        # when Label
        #   q.format(key)
        # when SymbolLiteral
        #   q.format(key.value)
        #   q.text(":")
        # when DynaSymbol
        #   parts = key.parts

        #   if parts.length == 1 && (part = parts.first) &&
        #        part.is_a?(TStringContent) && part.value.match?(LABEL)
        #     q.format(part)
        #     q.text(":")
        #   else
        #     q.format(key)
        #     q.text(":")
        #   end
      end
    end

    # Formats the keys of a hash literal using hash rockets.
    class Rockets
      def format_key(q, key)
        case key
        when SymbolNode

        when InterpolatedSymbolNode

        else
          q.format(key)
          q.text(" =>")
        end
      end
    end

    # When formatting a single assoc node without the context of the parent
    # hash, this formatter is used. It uses whatever is present in the node,
    # because there is nothing to be consistent with.
    class Identity
      def format_key(q, key)
        case key
        when SymbolNode
          q.slice(key.value_loc)
          q.text(":")
        when InterpolatedSymbolNode

        else
          q.format(key)
          q.text(" =>")
        end
      end
    end

    def self.for(q, element)
      if element.is_a?(AssocSplatNode)
        # Splat nodes do not impact the formatting choice.
      elsif element.value.nil?
        # If the value is nil, then it has been omitted. In this case we have
        # to match the existing formatting because standardizing would
        # potentially break the code. For example:
        #
        #     { first:, "second" => "value" }
        #
        return Identity.new
      else
        # Otherwise, we need to check the type of the key. If it's a label or
        # dynamic symbol, we can use labels. If it's a symbol literal then it
        # needs to match a certain pattern to be used as a label. If it's
        # anything else, then we need to use hash rockets.
        case (key = element.key)
        when SymbolNode
          if key.opening_loc.nil? && !key.closing_loc.nil?
            # Here it's a label.
          else
            # Otherwise we need to check the actual value of the symbol to see
            # if it would work as a label.
            value_loc = key.value_loc
            value = q.source.byteslice(value_loc.start_offset...value_loc.end_offset)
            return Rockets.new if !value.match?(/^[_A-Za-z]/) || value.end_with?("=")
          end
        when InterpolatedSymbolNode
          # Labels can be used if this is an interpolated symbol that begins
          # with a :. If not, then it's a %s symbol so we'll use hash rockets.
          return Rockets.new if q.source.byteslice(key.opening_loc, 1) != ":"
        else
          # Otherwise, we need to use hash rockets.
          return Rockets.new
        end
      end

      Labels.new
    end
  end

  module HashFormatter

    def format(q)
      delims = delimiters()
      q.group do
        q.text(delims[0]) if delims
        q.indent do
          q.breakable_space

          q.seplist(elements) do |element|
            if element.is_a?(AssocSplatNode)
              q.format(element)
            else
              HashKeyFormatter.for(q, element).format_key(q, element.key)
              q.indent do
                q.breakable_space
                q.format(element.value) if element.value
              end
            end
          end
        end
        q.breakable_space
        q.text(delims[1]) if delims
      end
    end

    private

    # return delimiter pair or nil
    def delimiters
      raise NotImplementedError
    end

  end

  module LiteralNode
    def format(q)
      q.slice(location)
    end
  end

  module LoopNode
    def format(q)
      keyword = q.source.byteslice(keyword_loc.start_offset...keyword_loc.end_offset)

      if statements
        q.group do
          q
            .if_break do
              q.text("#{keyword} ")
              q.nest(keyword.length + 1) { q.format(predicate) }

              if statements
                q.indent do
                  q.breakable_space
                  q.format(statements)
                end
              end

              q.breakable_space
              q.text("end")
            end
            .if_flat do
              q.format(statements)
              q.text(" #{keyword} ")
              q.format(predicate)
            end
        end
      else
        q.group do
          q.text("#{keyword} ")
          q.nest(keyword.length + 1) { q.format(predicate) }
          q.breakable_force
          q.text("end")
        end
      end
    end
  end

  module MatchNode
    def format(q)
      q.group do
        q.format(value)
        q.text(" ")
        q.slice(operator_loc)

        q.indent do
          q.breakable_space
          q.format(pattern)
        end
      end
    end
  end

  module BinaryOperationBaseFormatter
    def format(q)
      q.group do
        lhs(q)
        q.text(" ")
        q.slice(operator_loc)

        q.indent do
          q.breakable_space
          rhs(q)
        end
      end
    end

    private

    def lhs(q)
      raise NotImplementedError
    end

    def rhs(q)
      raise NotImplementedError
    end

  end

  module AndOrFormatter
    include BinaryOperationBaseFormatter

    private

    def lhs(q)
      q.format(left)
    end

    def rhs(q)
      q.format(right)
    end
  end

  module BinaryOperationFormatter
    include BinaryOperationBaseFormatter

    private

    def rhs(q)
      q.format(value)
    end
  end

  module CallOperationFormatter
    include BinaryOperationFormatter

    private

    def lhs(q)
      q.format(target)
    end
  end

  module VariableOperationFormatter
    include BinaryOperationFormatter

    private

    def lhs(q)
      q.slice(name_loc)
    end
  end

  module MetaConstantFormatter
     def format(q)
       q.text("__#{metaname()}__")
     end

     private

     def metaname
       raise NotImplementedError
     end
  end


  class Node
    def comments
      []
    end
  end

  class AliasNode
    def format(q)
      q.group do
        q.text("alias ")
        format_name(q, new_name)
        q.group do
          q.nest(6) do
            q.breakable_space
            format_name(q, old_name)
          end
        end
      end
    end

    private

    def format_name(q, name)
      if name.is_a?(SymbolNode)
        q.slice(name.value_loc)
      else
        q.format(name)
      end
    end
  end

  class AlternationPatternNode
    def format(q)
      q.group do
        q.format(left)
        q.text(" | ")
        q.format(right)
      end
    end
  end

  class AndNode
    include AndOrFormatter
  end

  class ArgumentsNode
    def format(q)
      parts = []
      arguments.each do |argument|
        if argument.is_a?(KeywordHashNode)
          parts.concat(argument.elements)
        else
          parts << argument
        end
      end

      q.seplist(parts) { |part| q.format(part) }
    end
  end

  class ArrayNode
    def format(q)
      if !opening_loc
        q.group { q.seplist(elements) { |element| q.format(element) } }
      elsif (opening = q.source.byteslice(opening_loc.start_offset, 3)).start_with?("%")
        q.group do
          q.text(opening)
          q.indent do
            q.breakable_empty
            q.seplist(elements, ->(q) { q.breakable_space }) { |element| q.format(element) }
          end
          q.breakable_empty
          q.slice(closing_loc)
        end
      else
        q.group do
          q.slice(opening_loc)
          q.indent do
            q.breakable_empty
            q.seplist(elements) { |element| q.format(element) }
          end
          q.breakable_empty
          q.slice(closing_loc)
        end
      end
    end
  end

  class ArrayPatternNode
    def format(q)
      q.group do
        q.format(constant) if constant
        q.text("[")

        parts = []
        parts.concat(requireds)
        parts << rest if rest
        parts.concat(posts)
        q.seplist(parts) { |part| q.format(part) }

        q.text("]")
      end
    end
  end

  class AssocNode
    def format(q)
      q.group do
        q.format(key)

        if value
          q.text(" =>") unless key.is_a? SymbolNode
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class AssocSplatNode
    def format(q)
      q.group do
        q.text("**")
        q.format(value) if value
      end
    end
  end

  class BackReferenceReadNode
    include LiteralNode
  end

  class BeginNode
    def format(q)
      q.group do
        q.text("begin")

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        if rescue_clause
          q.breakable_force
          q.format(rescue_clause)
        end

        if else_clause
          q.breakable_force
          q.format(else_clause)
        end

        if ensure_clause
          q.breakable_force
          q.format(ensure_clause)
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class BlockArgumentNode
    def format(q)
      q.text("&")
      q.format(expression) if expression
    end
  end

  class BlockNode
    def format(q)
      q.group do
        q.if_break { q.text("do") }.if_flat { q.text("{") }

        if parameters
          q.text(" ")
          q.format(parameters)
        end

        if statements
          q.indent do
            q.breakable_space
            q.format(statements)
          end
        end

        if parameters || statements
          q.breakable_space
        else
          q.if_break { q.text(" ") }
        end

        q.if_break { q.text("end") }.if_flat { q.text("}") }
      end
    end
  end

  class BlockParameterNode
    def format(q)
      q.group do
        q.text("&")
        q.slice(name_loc) if name_loc
      end
    end
  end

  class BlockParametersNode
    def format(q)
      q.group do
        q.slice(opening_loc) if opening_loc
        q.format(parameters) if parameters

        if locals.any?
          q.text("; ")
          q.seplist(locals) { |local| q.slice(local) }
        end

        q.slice(closing_loc) if closing_loc
      end
    end
  end

  class BreakNode
    include FlowControlNode
  end

  class CallNode
    def format(q)
      case name
      when "!"
        q.group do
          q.text("!")
          q.format(receiver)
        end
      when "**"
        q.group do
          q.format(receiver)
          q.text(name)
          q.format(arguments.arguments.first)
        end
      when "+", "<<", "=="
        q.group do
          q.format(receiver)
          q.text(" ")
          q.text(name)
          q.indent do
            q.breakable_space
            q.format(arguments.arguments.first)
          end
        end
      when "[]"
        q.group do
          q.format(receiver)
          q.text("[")

          q.indent do
            q.breakable_empty
            q.format(arguments) if arguments
          end

          q.breakable_empty
          q.text("]")
        end
      when "-@"
        q.group do
          q.text("-")
          q.format(receiver)
        end
      else
        if opening_loc
          q.format(receiver) if receiver
          q.slice(operator_loc) if operator_loc
          q.slice(message_loc)

          q.group do
            q.slice(opening_loc)
            q.indent do
              q.breakable_empty
              q.format(arguments) if arguments
            end
            q.breakable_empty
            q.slice(closing_loc)
          end

          if block
            q.text(" ")
            q.format(block)
          end
        else
          q.group do
            q.format(receiver) if receiver
            q.slice(operator_loc) if operator_loc
            q.slice(message_loc)
            q.slice(opening_loc) if opening_loc

            if arguments
              q.text(" ") unless opening_loc
              q.format(arguments)
            end

            q.slice(closing_loc) if closing_loc

            if block
              q.text(" ")
              q.format(block)
            end
          end
        end
      end
    end
  end

  class CallOperatorAndWriteNode
    include CallOperationFormatter
  end

  class CallOperatorOrWriteNode
    include CallOperationFormatter
  end

  class CallOperatorWriteNode
    include CallOperationFormatter
  end

  class CapturePatternNode
    def format(q)
      q.group do
        q.format(value)
        q.text(" => ")
        q.format(target)
      end
    end
  end

  class CaseNode
    def format(q)
      q.group do
        q.text("case")

        if predicate
          q.text(" ")
          q.nest(5) { q.format(predicate) }
        end

        conditions.each do |condition|
          q.breakable_force
          q.format(condition)
        end

        if consequent
          q.breakable_force
          q.format(consequent)
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class ClassNode
    def format(q)
      q.group do
        q.text("class ")
        q.group do
          q.format(constant_path)

          if superclass
            q.text(" < ")
            q.format(superclass)
          end
        end

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class ClassVariableOperatorAndWriteNode
    include VariableOperationFormatter
  end

  class ClassVariableOperatorOrWriteNode
    include VariableOperationFormatter
  end

  class ClassVariableOperatorWriteNode
    include VariableOperationFormatter
  end

  class ClassVariableReadNode
    include LiteralNode
  end

  class ClassVariableWriteNode
    def format(q)
      q.group do
        q.slice(name_loc)

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class ConstantOperatorAndWriteNode
    include VariableOperationFormatter
  end

  class ConstantOperatorOrWriteNode
    include VariableOperationFormatter
  end

  class ConstantOperatorWriteNode
    include VariableOperationFormatter
  end

  class ConstantPathNode
    def format(q)
      q.format(parent) if parent
      q.text("::")
      q.format(child)
    end
  end

  class ConstantPathOperatorWriteNode
    include CallOperationFormatter
  end

  class ConstantPathOperatorAndWriteNode
    include CallOperationFormatter
  end

  class ConstantPathOperatorOrWriteNode
    include CallOperationFormatter
  end

  class ConstantPathWriteNode
    def format(q)
      q.group do
        q.format(target)

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class ConstantReadNode
    include LiteralNode
  end

  class DefNode
    def format(q)
      q.group do
        q.group do
          q.text("def ")

          if receiver
            q.format(receiver)
            q.slice(operator_loc)
          end

          q.slice(name_loc)

          if !parameters
            q.text("()") if lparen_loc && rparen_loc
          else
            q.group do
              q.text("(")
              q.indent do
                q.breakable_empty
                q.format(parameters)
              end
              q.breakable_empty
              q.text(")")
            end
          end
        end

        if equal_loc
          q.text(" =")
          q.group do
            q.indent do
              q.breakable_space
              q.format(statements)
            end
          end
        else
          if statements
            q.indent do
              q.breakable_force
              q.format(statements)
            end
          end

          q.breakable_force
          q.text("end")
        end
      end
    end
  end

  class DefinedNode
    def format(q)
      q.group do
        q.text("defined?(")
        q.indent do
          q.breakable_empty
          q.format(value)
        end
        q.breakable_empty
        q.text(")")
      end
    end
  end

  class ElseNode
    def format(q)
      q.group do
        keyword = q.source.byteslice(else_keyword_loc.start_offset...else_keyword_loc.end_offset)

        if statements
          if keyword == "else"
            q.text(keyword)
            q.indent do
              q.breakable_force
              q.format(statements)
            end
          else # keyword == ":"
            q.group do
              q.breakable_space
              q.text(keyword)
              q.breakable_space
              q.format(statements)
            end
          end
        end
      end
    end
  end

  class EmbeddedStatementsNode
    def format(q)
      q.text("\#{")
      q.format(statements)
      q.text("}")
    end
  end

  class EmbeddedVariableNode
    def format(q)
      q.text("\#{")
      q.format(variable)
      q.text("}")
    end
  end

  class EnsureNode
    def format(q)
      q.group do
        q.text("ensure")

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end
      end
    end
  end

  class FalseNode
    include LiteralNode
  end

  class FindPatternNode
    def format(q)
      q.group do
        q.format(constant) if constant
        q.text("[")

        parts = [left]
        parts.concat(requireds)
        parts << right
        q.seplist(parts) { |part| q.format(part) }

        q.text("]")
      end
    end
  end

  class FloatNode
    include LiteralNode
  end

  class ForNode
    def format(q)
      q.group do
        q.text("for ")
        q.format(index)
        q.text(" in ")
        q.format(collection)

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class ForwardingArgumentsNode
    include LiteralNode
  end

  class ForwardingParameterNode
    include LiteralNode
  end

  class ForwardingSuperNode
    def format(q)
      q.text("super")

      if block
        q.text(" ")
        q.format(block)
      end
    end
  end

  class GlobalVariableReadNode
    include LiteralNode
  end

  class GlobalVariableWriteNode
    def format(q)
      q.group do
        q.slice(name_loc)

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class GlobalVariableOperatorAndWriteNode
    include VariableOperationFormatter
  end

  class GlobalVariableOperatorOrWriteNode
    include VariableOperationFormatter
  end

  class GlobalVariableOperatorWriteNode
    include VariableOperationFormatter
  end

  class HashNode
    include HashFormatter

    private

    def delimiters
      ["{", "}"]
    end

  end

  class HashPatternNode
    def format(q)
      parts = []
      parts.concat(assocs)
      parts << kwrest if kwrest

      q.group do
        if constant
          q.format(constant)
          q.text("[")
          q.indent do
            q.breakable_empty
            q.seplist(parts) { |part| q.format(part) }
          end
          q.breakable_empty
          q.text("]")
        elsif parts.any?
          q.text("{")
          q.indent do
            q.breakable_space
            q.seplist(parts) { |part| q.format(part) }
          end
          q.breakable_space
          q.text("}")
        else
          q.text("{}")
        end
      end
    end
  end

  class IfNode
    def format(q)
      if if_keyword_loc
        keyword = q.source.byteslice(if_keyword_loc.start_offset...if_keyword_loc.end_offset)

        if keyword == "if" && q.parent.is_a?(InNode) && q.parent.pattern == self
          q.group do
            q.format(statements)
            q.text(" if ")
            q.format(predicate)
          end
        else
          q.group do
            q.text(keyword)
            q.text(" ")
            q.nest(3) { q.format(predicate) }

            if statements
              q.indent do
                q.breakable_force
                q.format(statements)
              end
            end

            if consequent
              q.breakable_force
              q.format(consequent)
            end

            if keyword == "if"
              q.breakable_force
              q.text("end")
            end
          end
        end
      else # a ? b : c
        q.group do
          q.format(predicate)
          q.text(" ? ")
          q.format(statements)
          q.format(consequent)
        end
      end
    end
  end

  class ImaginaryNode
    include LiteralNode
  end

  class InNode
    def format(q)
      q.group do
        q.text("in ")
        q.nest(3) { q.format(pattern) }

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end
      end
    end
  end

  class InstanceVariableReadNode
    include LiteralNode
  end

  class InstanceVariableOperatorAndWriteNode
    include VariableOperationFormatter
  end

  class InstanceVariableOperatorOrWriteNode
    include VariableOperationFormatter
  end

  class InstanceVariableOperatorWriteNode
    include VariableOperationFormatter
  end

  class InstanceVariableWriteNode
    def format(q)
      q.group do
        q.slice(name_loc)

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class IntegerNode
    include LiteralNode
  end

  class InterpolatedRegularExpressionNode
    def format(q)
      q.group do
        q.text("/")
        q.format_each(parts)
        q.text("/")
      end
    end
  end

  class InterpolatedStringNode
    def format(q)
      if opening_loc && q.source.byteslice(opening_loc.start_offset, 2) == "<<"
        separator = PrettierPrint::Breakable.new(" ", 1, indent: false, force: true)

        q.group do
          q.slice(opening_loc)

          q.line_suffix(priority: SyntaxTree::Formatter::HEREDOC_PRIORITY) do
            q.group do
              q.target << separator
              
              parts.each do |part|
                if part.is_a?(StringNode)
                  content_loc = part.content_loc
                  value = q.source.byteslice(content_loc.start_offset...content_loc.end_offset)

                  first = true
                  value.each_line(chomp: true) do |line|
                    if first
                      first = false
                    else
                      q.target << separator
                    end
  
                    q.text(line)
                  end
  
                  q.target << separator if value.end_with?("\n")
                else
                  q.format(part)
                end
              end
  
              q.slice(closing_loc)
            end
          end
        end
      else
        q.group do
          q.slice(opening_loc) if opening_loc
          q.format_each(parts)
          q.slice(closing_loc) if closing_loc
        end
      end
    end
  end

  class InterpolatedSymbolNode
    def format(q)
      q.group do
        q.slice(opening_loc) if opening_loc
        q.format_each(parts)
        q.slice(closing_loc) if closing_loc
      end
    end
  end

  class InterpolatedXStringNode
    def format(q)
      q.group do
        q.text("`")
        q.format_each(parts)
        q.text("`")
      end
    end
  end

  class KeywordHashNode
    include HashFormatter

    private

    def delimiters
    end
  end

  class KeywordParameterNode
    def format(q)
      q.group do
        q.slice(name_loc)

        if value
          q.text(" ")
          q.format(value)
        end
      end
    end
  end

  class KeywordRestParameterNode
    def format(q)
      q.group do
        q.text("**")
        q.slice(name_loc) if name_loc
      end
    end
  end

  class LambdaNode
    def format(q)
      q.group do
        q.text("->")
        q.format(parameters) if parameters
        q.text(" ")
        q.group do
          q
            .if_break do
              q.text("do")

              if statements
                q.indent do
                  q.breakable_empty
                  q.format(statements)
                end
              end

              q.breakable_empty
              q.text("end")
            end
            .if_flat do
              if statements
                q.text("{ ")
                q.format(statements)
                q.text(" }")
              else
                q.text("{}")
              end
            end
        end
      end
    end
  end

  class LocalVariableOperatorAndWriteNode
    include VariableOperationFormatter
  end

  class LocalVariableOperatorOrWriteNode
    include VariableOperationFormatter
  end

  class LocalVariableOperatorWriteNode
    include VariableOperationFormatter
  end

  class LocalVariableReadNode
    include LiteralNode
  end

  class LocalVariableWriteNode
    def format(q)
      q.group do
        q.slice(name_loc)

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class MatchPredicateNode
    include MatchNode
  end

  class MatchRequiredNode
    include MatchNode
  end

  class ModuleNode
    def format(q)
      q.group do
        q.text("module ")
        q.format(constant_path)

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class MultiWriteNode
    def format(q)
      q.group do
        q.text("(") if lparen_loc
        q.seplist(targets) { |target| q.format(target) }
        q.text(")") if rparen_loc

        if value
          q.text(" =")
          q.indent do
            q.breakable_space
            q.format(value)
          end
        end
      end
    end
  end

  class NextNode
    include FlowControlNode
  end

  class NoKeywordsParameterNode
    include LiteralNode
  end

  class NilNode
    include LiteralNode
  end

  class NumberedReferenceReadNode
    include LiteralNode
  end

  class OptionalParameterNode
    def format(q)
      q.group do
        q.slice(name_loc)
        q.text(" =")
        q.indent do
          q.breakable_space
          q.format(value)
        end
      end
    end
  end

  class OrNode
    include AndOrFormatter
  end

  class ParametersNode
    def format(q)
      parts = []
      parts.concat(requireds)
      parts.concat(optionals)
      parts << rest if rest
      parts.concat(posts)
      parts.concat(keywords)
      parts << keyword_rest if keyword_rest
      parts << block if block

      q.seplist(parts) { |part| q.format(part) }
    end
  end

  class ParenthesesNode
    def format(q)
      q.group do
        q.text("(")

        if statements
          q.indent do
            q.breakable_empty
            q.format(statements)
          end

          q.breakable_empty
        end

        q.text(")")
      end
    end
  end

  class PinnedExpressionNode
    def format(q)
      q.group do
        q.text("^(")

        q.indent do
          q.breakable_empty
          q.format(expression)
        end

        q.breakable_empty
        q.text(")")
      end
    end
  end

  class PinnedVariableNode
    def format(q)
      q.text("^")
      q.format(variable)
    end
  end

  class PostExecutionNode
    def format(q)
      q.group do
        q.text("END {")
        q.indent do
          q.breakable_space
          q.format(statements)
        end
        q.breakable_space
        q.text("}")
      end
    end
  end

  class PreExecutionNode
    def format(q)
      q.group do
        q.text("BEGIN {")
        q.indent do
          q.breakable_space
          q.format(statements)
        end
        q.breakable_space
        q.text("}")
      end
    end
  end

  class ProgramNode
    def format(q)
      q.format(statements)
      q.breakable_force
    end
  end

  class RangeNode
    def format(q)
      q.group do
        q.format(left) if left

        case q.parent
        when IfNode, UnlessNode
          q.text(" ")
          q.slice(operator_loc)
          q.text(" ")
        else
          q.slice(operator_loc)
        end

        q.format(right) if right
      end
    end
  end

  class RationalNode
    include LiteralNode
  end

  class RedoNode
    include LiteralNode
  end

  class RegularExpressionNode
    def format(q)
      q.slice(opening_loc)
      q.slice(content_loc)
      q.slice(closing_loc)
    end
  end

  class RequiredParameterNode
    include LiteralNode
  end

  class RequiredDestructuredParameterNode
    def format(q)
      q.group do
        q.slice(opening_loc)
        q.seplist(parameters) { |parameter| q.format(parameter) }
        q.slice(closing_loc)
      end
    end
  end


  class RescueNode
    def format(q)
      q.group do
        q.text("rescue")

        q.group do
          if exceptions.any?
            q.text(" ")
            q.nest(7) { q.seplist(exceptions) { |exception| q.format(exception) } }
          else
            q.text(" StandardError")
          end

          if exception
            q.text(" => ")
            q.format(exception)
          end
        end

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        if consequent
          q.breakable_force
          q.format(consequent)
        end
      end
    end
  end

  class RescueModifierNode
    def format(q)
      q.group do
        q.text("begin")
        q.indent do
          q.breakable_force
          q.format(expression)
        end

        q.breakable_force
        q.text("rescue StandardError")

        q.indent do
          q.breakable_force
          q.format(rescue_expression)
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class RestParameterNode
    def format(q)
      q.group do
        q.text("*")
        q.slice(name_loc) if name_loc
      end
    end
  end

  class RetryNode
    include LiteralNode
  end

  class ReturnNode
    include FlowControlNode
  end

  class SelfNode
    include LiteralNode
  end

  class StatementsNode
    def format(q)
      offset = nil

      body.each do |statement|
        newlines =
          unless offset.nil?
            q.source.byteslice(offset...statement.location.start_offset).count("\n")
          end

        case newlines
        when nil
          q.format(statement)
        when 0
          q.text("; ")
          q.format(statement)
        when 1
          q.breakable_force
          q.format(statement)
        else
          q.breakable_force
          q.breakable_force
          q.format(statement)
        end

        offset = statement.location.end_offset
      end
    end
  end

  class SingletonClassNode
    def format(q)
      q.group do
        q.text("class << ")
        q.format(expression)

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end

        q.breakable_force
        q.text("end")
      end
    end
  end

  class SourceFileNode
    include MetaConstantFormatter

    private

    def metaname
      "FILE"
    end
  end

  class SourceLineNode
    include MetaConstantFormatter

    private

    def metaname
      "LINE"
    end
  end

  class SourceEncodingNode
    include MetaConstantFormatter

    private

    def metaname
      "ENCODING"
    end
  end

  class SplatNode
    def format(q)
      q.text("*")
      q.format(expression) if expression
    end
  end

  class StringNode
    def format(q)
      q.slice(opening_loc) if opening_loc
      q.slice(content_loc)
      q.slice(closing_loc) if closing_loc
    end
  end

  class StringConcatNode
    def format(q)
      q.group do
        q.format(left)
        q.text(" \\")
        q.indent do
          q.breakable_force
          q.format(right)
        end
      end
    end
  end

  class SuperNode
    def format(q)
      q.group do
        if lparen_loc && rparen_loc
          q.text("super(")
          q.indent do
            q.breakable_empty
            q.format(arguments) if arguments
          end

          q.breakable_empty
          q.text(")")
        else
          q.text("super ")
          q.nest(6) { q.format(arguments) }
        end

        if block
          q.text(" ")
          q.format(block)
        end
      end
    end
  end

  class SymbolNode
    def format(q)
      q.slice(opening_loc) if opening_loc
      q.slice(value_loc)
      q.slice(closing_loc) if closing_loc
    end
  end

  class TrueNode
    include LiteralNode
  end

  class UndefNode
    def format(q)
      q.group do
        q.text("undef ")
        q.nest(6) { q.seplist(names) { |name| q.format(name) } }
      end
    end
  end

  class UnlessNode
    def format(q)
      if !statements || consequent
        q.group do
          q.text("unless ")
          q.nest(7) { q.format(predicate) }

          if statements
            q.indent do
              q.breakable_force
              q.format(statements)
            end
          end

          if consequent
            q.breakable_force
            q.format(consequent)
          end

          q.breakable_force
          q.text("end")
        end
      else
        q.group do
          q
            .if_break do
              q.text("unless ")
              q.nest(7) { q.format(predicate) }
    
              if statements
                q.indent do
                  q.breakable_space
                  q.format(statements)
                end
              end
    
              q.breakable_space
              q.text("end")
            end
            .if_flat do
              if statements.body.size == 1
                q.format(statements)
                q.text(" unless ")
                q.format(predicate)
              else
                q.text("unless ")
                q.format(predicate)
                q.text(";")
                q.breakable_space
                q.format(statements)
                q.text(";")
                q.breakable_space
                q.text("end")
              end
            end
        end
      end
    end
  end

  class UntilNode
    include LoopNode
  end

  class WhenNode
    def format(q)
      q.group do
        q.text("when ")
        q.nest(5) { q.seplist(conditions) { |condition| q.format(condition) } }

        if statements
          q.indent do
            q.breakable_force
            q.format(statements)
          end
        end
      end
    end
  end

  class WhileNode
    include LoopNode
  end

  class XStringNode
    def format(q)
      q.group do
        q.text("`")
        q.slice(content_loc)
        q.text("`")
      end
    end
  end

  class YieldNode
    def format(q)
      q.group do
        q.text("yield")

        if arguments
          q.text(" ")
          q.format(arguments)
        end
      end
    end
  end
end
