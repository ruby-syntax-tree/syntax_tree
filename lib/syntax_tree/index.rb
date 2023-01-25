# frozen_string_literal: true

module SyntaxTree
  # This class can be used to build an index of the structure of Ruby files. We
  # define an index as the list of constants and methods defined within a file.
  #
  # This index strives to be as fast as possible to better support tools like
  # IDEs. Because of that, it has different backends depending on what
  # functionality is available.
  module Index
    # This is a location for an index entry.
    class Location
      attr_reader :line, :column

      def initialize(line, column)
        @line = line
        @column = column
      end
    end

    # This entry represents a class definition using the class keyword.
    class ClassDefinition
      attr_reader :nesting, :name, :location

      def initialize(nesting, name, location)
        @nesting = nesting
        @name = name
        @location = location
      end
    end

    # This entry represents a module definition using the module keyword.
    class ModuleDefinition
      attr_reader :nesting, :name, :location

      def initialize(nesting, name, location)
        @nesting = nesting
        @name = name
        @location = location
      end
    end

    # This entry represents a method definition using the def keyword.
    class MethodDefinition
      attr_reader :nesting, :name, :location

      def initialize(nesting, name, location)
        @nesting = nesting
        @name = name
        @location = location
      end
    end

    # This entry represents a singleton method definition using the def keyword
    # with a specified target.
    class SingletonMethodDefinition
      attr_reader :nesting, :name, :location

      def initialize(nesting, name, location)
        @nesting = nesting
        @name = name
        @location = location
      end
    end

    # This backend creates the index using RubyVM::InstructionSequence, which is
    # faster than using the Syntax Tree parser, but is not available on all
    # runtimes.
    class ISeqBackend
      VM_DEFINECLASS_TYPE_CLASS = 0x00
      VM_DEFINECLASS_TYPE_SINGLETON_CLASS = 0x01
      VM_DEFINECLASS_TYPE_MODULE = 0x02
      VM_DEFINECLASS_FLAG_SCOPED = 0x08
      VM_DEFINECLASS_FLAG_HAS_SUPERCLASS = 0x10

      def index(source)
        index_iseq(RubyVM::InstructionSequence.compile(source).to_a)
      end

      def index_file(filepath)
        index_iseq(RubyVM::InstructionSequence.compile_file(filepath).to_a)
      end

      private

      def index_iseq(iseq)
        results = []
        queue = [[iseq, []]]

        while (current_iseq, current_nesting = queue.shift)
          current_iseq[13].each_with_index do |insn, index|
            next unless insn.is_a?(Array)

            case insn[0]
            when :defineclass
              _, name, class_iseq, flags = insn

              if flags == VM_DEFINECLASS_TYPE_SINGLETON_CLASS
                # At the moment, we don't support singletons that aren't
                # defined on self. We could, but it would require more
                # emulation.
                if current_iseq[13][index - 2] != [:putself]
                  raise NotImplementedError,
                        "singleton class with non-self receiver"
                end
              elsif flags & VM_DEFINECLASS_TYPE_MODULE > 0
                code_location = class_iseq[4][:code_location]
                location = Location.new(code_location[0], code_location[1])
                results << ModuleDefinition.new(current_nesting, name, location)
              else
                code_location = class_iseq[4][:code_location]
                location = Location.new(code_location[0], code_location[1])
                results << ClassDefinition.new(current_nesting, name, location)
              end

              queue << [class_iseq, current_nesting + [name]]
            when :definemethod
              _, name, method_iseq = insn

              code_location = method_iseq[4][:code_location]
              location = Location.new(code_location[0], code_location[1])
              results << SingletonMethodDefinition.new(
                current_nesting,
                name,
                location
              )
            when :definesmethod
              _, name, method_iseq = insn

              code_location = method_iseq[4][:code_location]
              location = Location.new(code_location[0], code_location[1])
              results << MethodDefinition.new(current_nesting, name, location)
            end
          end
        end

        results
      end
    end

    # This backend creates the index using the Syntax Tree parser and a visitor.
    # It is not as fast as using the instruction sequences directly, but is
    # supported on all runtimes.
    class ParserBackend
      class IndexVisitor < Visitor
        attr_reader :results, :nesting

        def initialize
          @results = []
          @nesting = []
        end

        def visit_class(node)
          name = visit(node.constant).to_sym
          location =
            Location.new(node.location.start_line, node.location.start_column)

          results << ClassDefinition.new(nesting.dup, name, location)
          nesting << name

          super
          nesting.pop
        end

        def visit_const_ref(node)
          node.constant.value
        end

        def visit_def(node)
          name = node.name.value.to_sym
          location =
            Location.new(node.location.start_line, node.location.start_column)

          results << if node.target.nil?
            MethodDefinition.new(nesting.dup, name, location)
          else
            SingletonMethodDefinition.new(nesting.dup, name, location)
          end
        end

        def visit_module(node)
          name = visit(node.constant).to_sym
          location =
            Location.new(node.location.start_line, node.location.start_column)

          results << ModuleDefinition.new(nesting.dup, name, location)
          nesting << name

          super
          nesting.pop
        end

        def visit_program(node)
          super
          results
        end
      end

      def index(source)
        SyntaxTree.parse(source).accept(IndexVisitor.new)
      end

      def index_file(filepath)
        index(SyntaxTree.read(filepath))
      end
    end

    # The class defined here is used to perform the indexing, depending on what
    # functionality is available from the runtime.
    INDEX_BACKEND =
      defined?(RubyVM::InstructionSequence) ? ISeqBackend : ParserBackend

    # This method accepts source code and then indexes it.
    def self.index(source)
      INDEX_BACKEND.new.index(source)
    end

    # This method accepts a filepath and then indexes it.
    def self.index_file(filepath)
      INDEX_BACKEND.new.index_file(filepath)
    end
  end
end
