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
      attr_reader :nesting, :name, :location, :comments

      def initialize(nesting, name, location, comments)
        @nesting = nesting
        @name = name
        @location = location
        @comments = comments
      end
    end

    # This entry represents a module definition using the module keyword.
    class ModuleDefinition
      attr_reader :nesting, :name, :location, :comments

      def initialize(nesting, name, location, comments)
        @nesting = nesting
        @name = name
        @location = location
        @comments = comments
      end
    end

    # This entry represents a method definition using the def keyword.
    class MethodDefinition
      attr_reader :nesting, :name, :location, :comments

      def initialize(nesting, name, location, comments)
        @nesting = nesting
        @name = name
        @location = location
        @comments = comments
      end
    end

    # This entry represents a singleton method definition using the def keyword
    # with a specified target.
    class SingletonMethodDefinition
      attr_reader :nesting, :name, :location, :comments

      def initialize(nesting, name, location, comments)
        @nesting = nesting
        @name = name
        @location = location
        @comments = comments
      end
    end

    # When you're using the instruction sequence backend, this class is used to
    # lazily parse comments out of the source code.
    class FileComments
      # We use the ripper library to pull out source comments.
      class Parser < Ripper
        attr_reader :comments

        def initialize(*)
          super
          @comments = {}
        end

        def on_comment(value)
          comments[lineno] = value.chomp
        end
      end

      # This represents the Ruby source in the form of a file. When it needs to
      # be read we'll read the file.
      class FileSource
        attr_reader :filepath

        def initialize(filepath)
          @filepath = filepath
        end

        def source
          File.read(filepath)
        end
      end

      # This represents the Ruby source in the form of a string. When it needs
      # to be read the string is returned.
      class StringSource
        attr_reader :source

        def initialize(source)
          @source = source
        end
      end

      attr_reader :source

      def initialize(source)
        @source = source
      end

      def comments
        @comments ||= Parser.new(source.source).tap(&:parse).comments
      end
    end

    # This class handles parsing comments from Ruby source code in the case that
    # we use the instruction sequence backend. Because the instruction sequence
    # backend doesn't provide comments (since they are dropped) we provide this
    # interface to lazily parse them out.
    class EntryComments
      include Enumerable
      attr_reader :file_comments, :location

      def initialize(file_comments, location)
        @file_comments = file_comments
        @location = location
      end

      def each(&block)
        line = location.line - 1
        result = []

        while line >= 0 && (comment = file_comments.comments[line])
          result.unshift(comment)
          line -= 1
        end

        result.each(&block)
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
        index_iseq(
          RubyVM::InstructionSequence.compile(source).to_a,
          FileComments.new(FileComments::StringSource.new(source))
        )
      end

      def index_file(filepath)
        index_iseq(
          RubyVM::InstructionSequence.compile_file(filepath).to_a,
          FileComments.new(FileComments::FileSource.new(filepath))
        )
      end

      private

      def location_for(iseq)
        code_location = iseq[4][:code_location]
        Location.new(code_location[0], code_location[1])
      end

      def index_iseq(iseq, file_comments)
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
                location = location_for(class_iseq)
                results << ModuleDefinition.new(
                  current_nesting,
                  name,
                  location,
                  EntryComments.new(file_comments, location)
                )
              else
                location = location_for(class_iseq)
                results << ClassDefinition.new(
                  current_nesting,
                  name,
                  location,
                  EntryComments.new(file_comments, location)
                )
              end

              queue << [class_iseq, current_nesting + [name]]
            when :definemethod
              location = location_for(insn[2])
              results << MethodDefinition.new(
                current_nesting,
                insn[1],
                location,
                EntryComments.new(file_comments, location)
              )
            when :definesmethod
              if current_iseq[13][index - 1] != [:putself]
                raise NotImplementedError,
                      "singleton method with non-self receiver"
              end

              location = location_for(insn[2])
              results << SingletonMethodDefinition.new(
                current_nesting,
                insn[1],
                location,
                EntryComments.new(file_comments, location)
              )
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
        attr_reader :results, :nesting, :statements

        def initialize
          @results = []
          @nesting = []
          @statements = nil
        end

        def visit_class(node)
          name = visit(node.constant).to_sym
          location =
            Location.new(node.location.start_line, node.location.start_column)

          results << ClassDefinition.new(
            nesting.dup,
            name,
            location,
            comments_for(node)
          )

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
            MethodDefinition.new(
              nesting.dup,
              name,
              location,
              comments_for(node)
            )
          else
            SingletonMethodDefinition.new(
              nesting.dup,
              name,
              location,
              comments_for(node)
            )
          end
        end

        def visit_module(node)
          name = visit(node.constant).to_sym
          location =
            Location.new(node.location.start_line, node.location.start_column)

          results << ModuleDefinition.new(
            nesting.dup,
            name,
            location,
            comments_for(node)
          )

          nesting << name
          super
          nesting.pop
        end

        def visit_program(node)
          super
          results
        end

        def visit_statements(node)
          @statements = node
          super
        end

        private

        def comments_for(node)
          comments = []

          body = statements.body
          line = node.location.start_line - 1
          index = body.index(node) - 1

          while index >= 0 && body[index].is_a?(Comment) &&
                  (line - body[index].location.start_line < 2)
            comments.unshift(body[index].value)
            line = body[index].location.start_line
            index -= 1
          end

          comments
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
    def self.index(source, backend: INDEX_BACKEND.new)
      backend.index(source)
    end

    # This method accepts a filepath and then indexes it.
    def self.index_file(filepath, backend: INDEX_BACKEND.new)
      backend.index_file(filepath)
    end
  end
end
