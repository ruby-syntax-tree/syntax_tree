# frozen_string_literal: true

module SyntaxTree
  module YARV
    # ### Summary
    #
    # `adjuststack` accepts a single integer argument and removes that many
    # elements from the top of the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = [true]
    # x[0] ||= nil
    # x[0]
    # ~~~
    #
    class AdjustStack
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def to_a(_iseq)
        [:adjuststack, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `anytostring` ensures that the value on top of the stack is a string.
    #
    # It pops two values off the stack. If the first value is a string it
    # pushes it back on the stack. If the first value is not a string, it uses
    # Ruby's built in string coercion to coerce the second value to a string
    # and then pushes that back on the stack.
    #
    # This is used in conjunction with `objtostring` as a fallback for when an
    # object's `to_s` method does not return a string.
    #
    # ### Usage
    #
    # ~~~ruby
    # "#{5}"
    # ~~~
    #
    class AnyToString
      def to_a(_iseq)
        [:anytostring]
      end

      def length
        1
      end

      def pops
        2
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `branchif` has one argument: the jump index. It pops one value off the
    # stack: the jump condition.
    #
    # If the value popped off the stack is true, `branchif` jumps to
    # the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = true
    # x ||= "foo"
    # puts x
    # ~~~
    #
    class BranchIf
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def patch!(iseq)
        @label = iseq.label
      end

      def to_a(_iseq)
        [:branchif, label]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `branchnil` has one argument: the jump index. It pops one value off the
    # stack: the jump condition.
    #
    # If the value popped off the stack is nil, `branchnil` jumps to
    # the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # x = nil
    # if x&.to_s
    #   puts "hi"
    # end
    # ~~~
    #
    class BranchNil
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def patch!(iseq)
        @label = iseq.label
      end

      def to_a(_iseq)
        [:branchnil, label]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `branchunless` has one argument: the jump index. It pops one value off
    # the stack: the jump condition.
    #
    # If the value popped off the stack is false or nil, `branchunless` jumps
    # to the jump index and continues executing there.
    #
    # ### Usage
    #
    # ~~~ruby
    # if 2 + 3
    #   puts "foo"
    # end
    # ~~~
    #
    class BranchUnless
      attr_reader :label

      def initialize(label)
        @label = label
      end

      def patch!(iseq)
        @label = iseq.label
      end

      def to_a(_iseq)
        [:branchunless, label]
      end

      def length
        2
      end

      def pops
        1
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `checkkeyword` checks if a keyword was passed at the callsite that
    # called into the method represented by the instruction sequence. It has
    # two arguments: the index of the local variable that stores the keywords
    # metadata and the index of the keyword within that metadata. It pushes
    # a boolean onto the stack indicating whether or not the keyword was
    # given.
    #
    # ### Usage
    #
    # ~~~ruby
    # def evaluate(value: rand)
    #   value
    # end
    #
    # evaluate(value: 3)
    # ~~~
    #
    class CheckKeyword
      attr_reader :keyword_bits_index, :keyword_index

      def initialize(keyword_bits_index, keyword_index)
        @keyword_bits_index = keyword_bits_index
        @keyword_index = keyword_index
      end

      def patch!(iseq)
        @label = iseq.label
      end

      def to_a(iseq)
        [
          :checkkeyword,
          iseq.local_table.offset(keyword_bits_index),
          keyword_index
        ]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `concatarray` concatenates the two Arrays on top of the stack.
    #
    # It coerces the two objects at the top of the stack into Arrays by
    # calling `to_a` if necessary, and makes sure to `dup` the first Array if
    # it was already an Array, to avoid mutating it when concatenating.
    #
    # ### Usage
    #
    # ~~~ruby
    # [1, *2]
    # ~~~
    #
    class ConcatArray
      def to_a(_iseq)
        [:concatarray]
      end

      def length
        1
      end

      def pops
        2
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `concatstrings` pops a number of strings from the stack joins them
    # together into a single string and pushes that string back on the stack.
    #
    # This does no coercion and so is always used in conjunction with
    # `objtostring` and `anytostring` to ensure the stack contents are always
    # strings.
    #
    # ### Usage
    #
    # ~~~ruby
    # "#{5}"
    # ~~~
    #
    class ConcatStrings
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def to_a(_iseq)
        [:concatstrings, number]
      end

      def length
        2
      end

      def pops
        number
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `defineclass` defines a class. First it pops the superclass off the
    # stack, then it pops the object off the stack that the class should be
    # defined under. It has three arguments: the name of the constant, the
    # instruction sequence associated with the class, and various flags that
    # indicate if it is a singleton class, a module, or a regular class.
    #
    # ### Usage
    #
    # ~~~ruby
    # class Foo
    # end
    # ~~~
    #
    class DefineClass
      TYPE_CLASS = 0
      TYPE_SINGLETON_CLASS = 1
      TYPE_MODULE = 2
      FLAG_SCOPED = 8
      FLAG_HAS_SUPERCLASS = 16

      attr_reader :name, :class_iseq, :flags

      def initialize(name, class_iseq, flags)
        @name = name
        @class_iseq = class_iseq
        @flags = flags
      end

      def to_a(_iseq)
        [:defineclass, name, class_iseq.to_a, flags]
      end

      def length
        4
      end

      def pops
        2
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `defined` checks if the top value of the stack is defined. If it is, it
    # pushes its value onto the stack. Otherwise it pushes `nil`.
    #
    # ### Usage
    #
    # ~~~ruby
    # defined?(x)
    # ~~~
    #
    class Defined
      TYPE_NIL = 1
      TYPE_IVAR = 2
      TYPE_LVAR = 3
      TYPE_GVAR = 4
      TYPE_CVAR = 5
      TYPE_CONST = 6
      TYPE_METHOD = 7
      TYPE_YIELD = 8
      TYPE_ZSUPER = 9
      TYPE_SELF = 10
      TYPE_TRUE = 11
      TYPE_FALSE = 12
      TYPE_ASGN = 13
      TYPE_EXPR = 14
      TYPE_REF = 15
      TYPE_FUNC = 16
      TYPE_CONST_FROM = 17

      attr_reader :type, :name, :message

      def initialize(type, name, message)
        @type = type
        @name = name
        @message = message
      end

      def to_a(_iseq)
        [:defined, type, name, message]
      end

      def length
        4
      end

      def pops
        1
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `definemethod` defines a method on the class of the current value of
    # `self`. It accepts two arguments. The first is the name of the method
    # being defined. The second is the instruction sequence representing the
    # body of the method.
    #
    # ### Usage
    #
    # ~~~ruby
    # def value = "value"
    # ~~~
    #
    class DefineMethod
      attr_reader :name, :method_iseq

      def initialize(name, method_iseq)
        @name = name
        @method_iseq = method_iseq
      end

      def to_a(_iseq)
        [:definemethod, name, method_iseq.to_a]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `definesmethod` defines a method on the singleton class of the current
    # value of `self`. It accepts two arguments. The first is the name of the
    # method being defined. The second is the instruction sequence representing
    # the body of the method. It pops the object off the stack that the method
    # should be defined on.
    #
    # ### Usage
    #
    # ~~~ruby
    # def self.value = "value"
    # ~~~
    #
    class DefineSMethod
      attr_reader :name, :method_iseq

      def initialize(name, method_iseq)
        @name = name
        @method_iseq = method_iseq
      end

      def to_a(_iseq)
        [:definesmethod, name, method_iseq.to_a]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        0
      end
    end

    # ### Summary
    #
    # `dup` copies the top value of the stack and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # $global = 5
    # ~~~
    #
    class Dup
      def to_a(_iseq)
        [:dup]
      end

      def length
        1
      end

      def pops
        1
      end

      def pushes
        2
      end
    end

    # ### Summary
    #
    # `duparray` dups an Array literal and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # [true]
    # ~~~
    #
    class DupArray
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def to_a(_iseq)
        [:duparray, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `duphash` dups a Hash literal and pushes it onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # { a: 1 }
    # ~~~
    #
    class DupHash
      attr_reader :object

      def initialize(object)
        @object = object
      end

      def to_a(_iseq)
        [:duphash, object]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `dupn` duplicates the top `n` stack elements.
    #
    # ### Usage
    #
    # ~~~ruby
    # Object::X ||= true
    # ~~~
    #
    class DupN
      attr_reader :number

      def initialize(number)
        @number = number
      end

      def to_a(_iseq)
        [:dupn, number]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        number
      end
    end

    # ### Summary
    #
    # `expandarray` looks at the top of the stack, and if the value is an array
    # it replaces it on the stack with `number` elements of the array, or `nil`
    # if the elements are missing.
    #
    # ### Usage
    #
    # ~~~ruby
    # x, = [true, false, nil]
    # ~~~
    #
    class ExpandArray
      attr_reader :number, :flags

      def initialize(number, flags)
        @number = number
        @flags = flags
      end

      def to_a(_iseq)
        [:expandarray, number, flags]
      end

      def length
        3
      end

      def pops
        1
      end

      def pushes
        number
      end
    end

    # ### Summary
    #
    # `getblockparam` is a similar instruction to `getlocal` in that it looks
    # for a local variable in the current instruction sequence's local table and
    # walks recursively up the parent instruction sequences until it finds it.
    # The local it retrieves, however, is a special block local that was passed
    # to the current method. It pushes the value of the block local onto the
    # stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(&block)
    #   block
    # end
    # ~~~
    #
    class GetBlockParam
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def to_a(iseq)
        current = iseq
        level.times { current = iseq.parent_iseq }
        [:getblockparam, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getblockparamproxy` is almost the same as `getblockparam` except that it
    # pushes a proxy object onto the stack instead of the actual value of the
    # block local. This is used when a method is being called on the block
    # local.
    #
    # ### Usage
    #
    # ~~~ruby
    # def foo(&block)
    #   block.call
    # end
    # ~~~
    #
    class GetBlockParamProxy
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def to_a(iseq)
        current = iseq
        level.times { current = iseq.parent_iseq }
        [:getblockparamproxy, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getclassvariable` looks for a class variable in the current class and
    # pushes its value onto the stack. It uses an inline cache to reduce the
    # need to lookup the class variable in the class hierarchy every time.
    #
    # ### Usage
    #
    # ~~~ruby
    # @@class_variable
    # ~~~
    #
    class GetClassVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def to_a(_iseq)
        [:getclassvariable, name, cache]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getglobal` pushes the value of a global variables onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # $$
    # ~~~
    #
    class GetGlobal
      attr_reader :name

      def initialize(name)
        @name = name
      end

      def to_a(_iseq)
        [:getglobal, name]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getinstancevariable` pushes the value of an instance variable onto the
    # stack. It uses an inline cache to avoid having to look up the instance
    # variable in the class hierarchy every time.
    #
    # This instruction has two forms, but both have the same structure. Before
    # Ruby 3.2, the inline cache corresponded to both the get and set
    # instructions and could be shared. Since Ruby 3.2, it uses object shapes
    # instead so the caches are unique per instruction.
    #
    # ### Usage
    #
    # ~~~ruby
    # @instance_variable
    # ~~~
    #
    class GetInstanceVariable
      attr_reader :name, :cache

      def initialize(name, cache)
        @name = name
        @cache = cache
      end

      def to_a(_iseq)
        [:getinstancevariable, name, cache]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getlocal_WC_0` is a specialized version of the `getlocal` instruction. It
    # fetches the value of a local variable from the current frame determined by
    # the index given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # value
    # ~~~
    #
    class GetLocalWC0
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def to_a(iseq)
        [:getlocal_WC_0, iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getlocal_WC_1` is a specialized version of the `getlocal` instruction. It
    # fetches the value of a local variable from the parent frame determined by
    # the index given as its only argument.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # self.then { value }
    # ~~~
    #
    class GetLocalWC1
      attr_reader :index

      def initialize(index)
        @index = index
      end

      def to_a(iseq)
        [:getlocal_WC_1, iseq.parent_iseq.local_table.offset(index)]
      end

      def length
        2
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # ### Summary
    #
    # `getlocal` fetches the value of a local variable from a frame determined
    # by the level and index arguments. The level is the number of frames back
    # to look and the index is the index in the local table. It pushes the value
    # it finds onto the stack.
    #
    # ### Usage
    #
    # ~~~ruby
    # value = 5
    # tap { tap { value } }
    # ~~~
    #
    class GetLocal
      attr_reader :index, :level

      def initialize(index, level)
        @index = index
        @level = level
      end

      def to_a(iseq)
        current = iseq
        level.times { current = current.parent_iseq }
        [:getlocal, current.local_table.offset(index), level]
      end

      def length
        3
      end

      def pops
        0
      end

      def pushes
        1
      end
    end

    # This module contains the instructions that used to be a part of YARV but
    # have been replaced or removed in more recent versions.
    module Legacy
      # ### Summary
      #
      # `getclassvariable` looks for a class variable in the current class and
      # pushes its value onto the stack.
      #
      # This version of the `getclassvariable` instruction is no longer used
      # since in Ruby 3.0 it gained an inline cache.`
      #
      # ### Usage
      #
      # ~~~ruby
      # @@class_variable
      # ~~~
      #
      class GetClassVariable
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_a(_iseq)
          [:getclassvariable, name]
        end

        def length
          2
        end

        def pops
          0
        end

        def pushes
          1
        end
      end

      # ### Summary
      #
      # `getconstant` performs a constant lookup and pushes the value of the
      # constant onto the stack. It pops both the class it should look in and
      # whether or not it should look globally as well.
      #
      # This instruction is no longer used since in Ruby 3.2 it was replaced by
      # the consolidated `opt_getconstant_path` instruction.
      #
      # ### Usage
      #
      # ~~~ruby
      # Constant
      # ~~~
      #
      class GetConstant
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def to_a(_iseq)
          [:getconstant, name]
        end

        def length
          2
        end

        def pops
          2
        end

        def pushes
          1
        end
      end
    end
  end
end
