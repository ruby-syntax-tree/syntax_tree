# frozen_string_literal: true

class SyntaxTree
  class Implicits
    attr_reader :before, :after

    def initialize
      @before = Hash.new { |hash, key| hash[key] = +"" }
      @after = Hash.new { |hash, key| hash[key] = +"" }
    end

    # Adds the implicitly rescued StandardError into a bare rescue clause. For
    # example,
    #
    #     begin
    #     rescue
    #     end
    #
    # becomes
    #
    #     begin
    #     rescue StandardError
    #     end
    #
    def bare_rescue(location)
      after[location.start_char + "rescue".length] << " StandardError"
    end

    # Adds the implicitly referenced value (local variable or method call) that
    # is added into a hash when the value of a key-value pair is omitted. For
    # example,
    #
    #     { value: }
    #
    # becomes
    #
    #     { value: value }
    #
    def missing_hash_value(key, location)
      after[location.end_char] << " #{key}"
    end

    # Adds implicit parentheses around certain expressions to make it clear
    # which subexpression will be evaluated first. For example,
    #
    #     a + b * c
    #
    # becomes
    #
    #     a + ₍b * c₎
    #
    def precedence_parentheses(location)
      before[location.start_char] << "₍"
      after[location.end_char] << "₎"
    end

    def self.find(program)
      implicits = new
      queue = [[nil, program]]

      until queue.empty?
        parent_node, child_node = queue.shift

        child_node.child_nodes.each do |grand_child_node|
          queue << [child_node, grand_child_node] if grand_child_node
        end

        case [parent_node, child_node]
        in _, Rescue[exception: nil, location:]
          implicits.bare_rescue(location)
        in _, Assoc[key: Label[value: key], value: nil, location:]
          implicits.missing_hash_value(key[0...-1], location)
        in Assign | Binary | IfOp | OpAssign, IfOp[location:]
          implicits.precedence_parentheses(location)
        in Assign | OpAssign, Binary[location:]
          implicits.precedence_parentheses(location)
        in Binary[operator: parent_oper], Binary[operator: child_oper, location:] if parent_oper != child_oper
          implicits.precedence_parentheses(location)
        in Binary, Unary[operator: "-", location:]
          implicits.precedence_parentheses(location)
        in Params, Assign[location:]
          implicits.precedence_parentheses(location)
        else
          # do nothing
        end
      end

      implicits
    end
  end
end
