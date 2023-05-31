# frozen_string_literal: true

module SyntaxTree
  module YARV
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
      class GetClassVariable < Instruction
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def disasm(fmt)
          fmt.instruction("getclassvariable", [fmt.object(name)])
        end

        def to_a(_iseq)
          [:getclassvariable, name]
        end

        def deconstruct_keys(_keys)
          { name: name }
        end

        def ==(other)
          other.is_a?(GetClassVariable) && other.name == name
        end

        def length
          2
        end

        def pushes
          1
        end

        def canonical
          YARV::GetClassVariable.new(name, nil)
        end

        def call(vm)
          canonical.call(vm)
        end
      end

      # ### Summary
      #
      # `opt_getinlinecache` is a wrapper around a series of `putobject` and
      # `getconstant` instructions that allows skipping past them if the inline
      # cache is currently set. It pushes the value of the cache onto the stack
      # if it is set, otherwise it pushes `nil`.
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
      class OptGetInlineCache < Instruction
        attr_reader :label, :cache

        def initialize(label, cache)
          @label = label
          @cache = cache
        end

        def disasm(fmt)
          fmt.instruction(
            "opt_getinlinecache",
            [fmt.label(label), fmt.inline_storage(cache)]
          )
        end

        def to_a(_iseq)
          [:opt_getinlinecache, label.name, cache]
        end

        def deconstruct_keys(_keys)
          { label: label, cache: cache }
        end

        def ==(other)
          other.is_a?(OptGetInlineCache) && other.label == label &&
            other.cache == cache
        end

        def length
          3
        end

        def pushes
          1
        end

        def call(vm)
          vm.push(nil)
        end

        def branch_targets
          [label]
        end

        def falls_through?
          true
        end
      end

      # ### Summary
      #
      # `opt_newarray_max` is a specialization that occurs when the `max` method
      # is called on an array literal. It pops the values of the array off the
      # stack and pushes on the result.
      #
      # ### Usage
      #
      # ~~~ruby
      # [a, b, c].max
      # ~~~
      #
      class OptNewArrayMax < Instruction
        attr_reader :number

        def initialize(number)
          @number = number
        end

        def disasm(fmt)
          fmt.instruction("opt_newarray_max", [fmt.object(number)])
        end

        def to_a(_iseq)
          [:opt_newarray_max, number]
        end

        def deconstruct_keys(_keys)
          { number: number }
        end

        def ==(other)
          other.is_a?(OptNewArrayMax) && other.number == number
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

        def call(vm)
          vm.push(vm.pop(number).max)
        end
      end

      # ### Summary
      #
      # `opt_newarray_min` is a specialization that occurs when the `min` method
      # is called on an array literal. It pops the values of the array off the
      # stack and pushes on the result.
      #
      # ### Usage
      #
      # ~~~ruby
      # [a, b, c].min
      # ~~~
      #
      class OptNewArrayMin < Instruction
        attr_reader :number

        def initialize(number)
          @number = number
        end

        def disasm(fmt)
          fmt.instruction("opt_newarray_min", [fmt.object(number)])
        end

        def to_a(_iseq)
          [:opt_newarray_min, number]
        end

        def deconstruct_keys(_keys)
          { number: number }
        end

        def ==(other)
          other.is_a?(OptNewArrayMin) && other.number == number
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

        def call(vm)
          vm.push(vm.pop(number).min)
        end
      end

      # ### Summary
      #
      # `opt_setinlinecache` sets an inline cache for a constant lookup. It pops
      # the value it should set off the top of the stack. It uses this value to
      # set the cache. It then pushes that value back onto the top of the stack.
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
      class OptSetInlineCache < Instruction
        attr_reader :cache

        def initialize(cache)
          @cache = cache
        end

        def disasm(fmt)
          fmt.instruction("opt_setinlinecache", [fmt.inline_storage(cache)])
        end

        def to_a(_iseq)
          [:opt_setinlinecache, cache]
        end

        def deconstruct_keys(_keys)
          { cache: cache }
        end

        def ==(other)
          other.is_a?(OptSetInlineCache) && other.cache == cache
        end

        def length
          2
        end

        def pops
          1
        end

        def pushes
          1
        end

        def call(vm)
        end
      end

      # ### Summary
      #
      # `setclassvariable` looks for a class variable in the current class and
      # sets its value to the value it pops off the top of the stack.
      #
      # This version of the `setclassvariable` instruction is no longer used
      # since in Ruby 3.0 it gained an inline cache.
      #
      # ### Usage
      #
      # ~~~ruby
      # @@class_variable = 1
      # ~~~
      #
      class SetClassVariable < Instruction
        attr_reader :name

        def initialize(name)
          @name = name
        end

        def disasm(fmt)
          fmt.instruction("setclassvariable", [fmt.object(name)])
        end

        def to_a(_iseq)
          [:setclassvariable, name]
        end

        def deconstruct_keys(_keys)
          { name: name }
        end

        def ==(other)
          other.is_a?(SetClassVariable) && other.name == name
        end

        def length
          2
        end

        def pops
          1
        end

        def canonical
          YARV::SetClassVariable.new(name, nil)
        end

        def call(vm)
          canonical.call(vm)
        end
      end
    end
  end
end
