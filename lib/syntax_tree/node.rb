# frozen_string_literal: true

module SyntaxTree
  # Represents the location of a node in the tree from the source code.
  class Location
    attr_reader :start_line, :start_char, :start_column, :end_line, :end_char, :end_column

    def initialize(start_line:, start_char:, start_column:, end_line:, end_char:, end_column:)
      @start_line = start_line
      @start_char = start_char
      @start_column = start_column
      @end_line = end_line
      @end_char = end_char
      @end_column = end_column
    end

    def lines
      start_line..end_line
    end

    def ==(other)
      other.is_a?(Location) && start_line == other.start_line &&
        start_char == other.start_char && end_line == other.end_line &&
        end_char == other.end_char
    end

    def to(other)
      Location.new(
        start_line: start_line,
        start_char: start_char,
        start_column: start_column,
        end_line: [end_line, other.end_line].max,
        end_char: other.end_char,
        end_column: other.end_column
      )
    end

    def deconstruct
      [start_line, start_char, start_column, end_line, end_char, end_column]
    end

    def deconstruct_keys(keys)
      {
        start_line: start_line,
        start_char: start_char,
        start_column: start_column,
        end_line: end_line,
        end_char: end_char,
        end_column: end_column
      }
    end

    def self.token(line:, char:, column:, size:)
      new(
        start_line: line,
        start_char: char,
        start_column: column,
        end_line: line,
        end_char: char + size,
        end_column: column + size
      )
    end

    def self.fixed(line:, char:, column:)
      new(start_line: line, start_char: char, start_column: column, end_line: line, end_char: char, end_column: column)
    end
  end

  # This is the parent node of all of the syntax tree nodes. It's pretty much
  # exclusively here to make it easier to operate with the tree in cases where
  # you're trying to monkey-patch or strictly type.
  class Node
    # [Location] the location of this node
    attr_reader :location

    def accept(visitor)
      raise NotImplementedError
    end

    def child_nodes
      raise NotImplementedError
    end

    def deconstruct
      raise NotImplementedError
    end

    def deconstruct_keys(keys)
      raise NotImplementedError
    end

    def format(q)
      raise NotImplementedError
    end

    def pretty_print(q)
      visitor = Visitor::PrettyPrintVisitor.new(q)
      visitor.visit(self)
    end

    def to_json(*opts)
      visitor = Visitor::JSONVisitor.new
      visitor.visit(self).to_json(*opts)
    end
  end

  # BEGINBlock represents the use of the +BEGIN+ keyword, which hooks into the
  # lifecycle of the interpreter. Whatever is inside the block will get executed
  # when the program starts.
  #
  #     BEGIN {
  #     }
  #
  # Interestingly, the BEGIN keyword doesn't allow the do and end keywords for
  # the block. Only braces are permitted.
  class BEGINBlock < Node
    # [LBrace] the left brace that is seen after the keyword
    attr_reader :lbrace

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbrace:, statements:, location:, comments: [])
      @lbrace = lbrace
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_BEGIN(self)
    end

    def child_nodes
      [lbrace, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        lbrace: lbrace,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.text("BEGIN ")
        q.format(lbrace)
        q.indent do
          q.breakable
          q.format(statements)
        end
        q.breakable
        q.text("}")
      end
    end
  end

  # CHAR irepresents a single codepoint in the script encoding.
  #
  #     ?a
  #
  # In the example above, the CHAR node represents the string literal "a". You
  # can use control characters with this as well, as in ?\C-a.
  class CHAR < Node
    # [String] the value of the character literal
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_CHAR(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      if value.length != 2
        q.text(value)
      else
        q.text(q.quote)
        q.text(value[1] == "\"" ? "\\\"" : value[1])
        q.text(q.quote)
      end
    end
  end

  # ENDBlock represents the use of the +END+ keyword, which hooks into the
  # lifecycle of the interpreter. Whatever is inside the block will get executed
  # when the program ends.
  #
  #     END {
  #     }
  #
  # Interestingly, the END keyword doesn't allow the do and end keywords for the
  # block. Only braces are permitted.
  class ENDBlock < Node
    # [LBrace] the left brace that is seen after the keyword
    attr_reader :lbrace

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbrace:, statements:, location:, comments: [])
      @lbrace = lbrace
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_END(self)
    end

    def child_nodes
      [lbrace, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        lbrace: lbrace,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.text("END ")
        q.format(lbrace)
        q.indent do
          q.breakable
          q.format(statements)
        end
        q.breakable
        q.text("}")
      end
    end
  end

  # EndContent represents the use of __END__ syntax, which allows individual
  # scripts to keep content after the main ruby code that can be read through
  # the DATA constant.
  #
  #     puts DATA.read
  #
  #     __END__
  #     some other content that is not executed by the program
  #
  class EndContent < Node
    # [String] the content after the script
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit___end__(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("__END__")
      q.breakable(force: true)

      separator = -> { q.breakable(indent: false, force: true) }
      q.seplist(value.split(/\r?\n/, -1), separator) { |line| q.text(line) }
    end
  end

  # Alias represents the use of the +alias+ keyword with regular arguments (not
  # global variables). The +alias+ keyword is used to make a method respond to
  # another name as well as the current one.
  #
  #     alias aliased_name name
  #
  # For the example above, in the current context you can now call aliased_name
  # and it will execute the name method. When you're aliasing two methods, you
  # can either provide bare words (like the example above) or you can provide
  # symbols (note that this includes dynamic symbols like
  # :"left-#{middle}-right").
  class Alias < Node
    class AliasArgumentFormatter
      # [DynaSymbol | SymbolLiteral] the argument being passed to alias
      attr_reader :argument

      def initialize(argument)
        @argument = argument
      end

      def comments
        if argument.is_a?(SymbolLiteral)
          argument.comments + argument.value.comments
        else
          argument.comments
        end
      end

      def format(q)
        if argument.is_a?(SymbolLiteral)
          q.format(argument.value)
        else
          q.format(argument)
        end
      end
    end

    # [DynaSymbol | SymbolLiteral] the new name of the method
    attr_reader :left

    # [DynaSymbol | SymbolLiteral] the old name of the method
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:, comments: [])
      @left = left
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_alias(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { left: left, right: right, location: location, comments: comments }
    end

    def format(q)
      keyword = "alias "
      left_argument = AliasArgumentFormatter.new(left)

      q.group do
        q.text(keyword)
        q.format(left_argument, stackable: false)
        q.group do
          q.nest(keyword.length) do
            q.breakable(force: left_argument.comments.any?)
            q.format(AliasArgumentFormatter.new(right), stackable: false)
          end
        end
      end
    end
  end

  # ARef represents when you're pulling a value out of a collection at a
  # specific index. Put another way, it's any time you're calling the method
  # #[].
  #
  #     collection[index]
  #
  # The nodes usually contains two children, the collection and the index. In
  # some cases, you don't necessarily have the second child node, because you
  # can call procs with a pretty esoteric syntax. In the following example, you
  # wouldn't have a second child node:
  #
  #     collection[]
  #
  class ARef < Node
    # [untyped] the value being indexed
    attr_reader :collection

    # [nil | Args] the value being passed within the brackets
    attr_reader :index

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(collection:, index:, location:, comments: [])
      @collection = collection
      @index = index
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_aref(self)
    end

    def child_nodes
      [collection, index]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        collection: collection,
        index: index,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(collection)
        q.text("[")

        if index
          q.indent do
            q.breakable("")
            q.format(index)
          end
          q.breakable("")
        end

        q.text("]")
      end
    end
  end

  # ARefField represents assigning values into collections at specific indices.
  # Put another way, it's any time you're calling the method #[]=. The
  # ARefField node itself is just the left side of the assignment, and they're
  # always wrapped in assign nodes.
  #
  #     collection[index] = value
  #
  class ARefField < Node
    # [untyped] the value being indexed
    attr_reader :collection

    # [nil | Args] the value being passed within the brackets
    attr_reader :index

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(collection:, index:, location:, comments: [])
      @collection = collection
      @index = index
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_aref_field(self)
    end

    def child_nodes
      [collection, index]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        collection: collection,
        index: index,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(collection)
        q.text("[")

        if index
          q.indent do
            q.breakable("")
            q.format(index)
          end
          q.breakable("")
        end

        q.text("]")
      end
    end
  end

  # ArgParen represents wrapping arguments to a method inside a set of
  # parentheses.
  #
  #     method(argument)
  #
  # In the example above, there would be an ArgParen node around the Args node
  # that represents the set of arguments being sent to the method method. The
  # argument child node can be +nil+ if no arguments were passed, as in:
  #
  #     method()
  #
  class ArgParen < Node
    # [nil | Args | ArgsForward] the arguments inside the
    # parentheses
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_arg_paren(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      unless arguments
        q.text("()")
        return
      end

      q.group(0, "(", ")") do
        q.indent do
          q.breakable("")
          q.format(arguments)
        end
        q.breakable("")
      end
    end
  end

  # Args represents a list of arguments being passed to a method call or array
  # literal.
  #
  #     method(first, second, third)
  #
  class Args < Node
    # [Array[ untyped ]] the arguments that this node wraps
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:, comments: [])
      @parts = parts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_args(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
    end
  end

  # ArgBlock represents using a block operator on an expression.
  #
  #     method(&expression)
  #
  class ArgBlock < Node
    # [nil | untyped] the expression being turned into a block
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_arg_block(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("&")
      q.format(value) if value
    end
  end

  # Star represents using a splat operator on an expression.
  #
  #     method(*arguments)
  #
  class ArgStar < Node
    # [nil | untyped] the expression being splatted
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_arg_star(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("*")
      q.format(value) if value
    end
  end

  # ArgsForward represents forwarding all kinds of arguments onto another method
  # call.
  #
  #     def request(method, path, **headers, &block); end
  #
  #     def get(...)
  #       request(:GET, ...)
  #     end
  #
  #     def post(...)
  #       request(:POST, ...)
  #     end
  #
  # In the example above, both the get and post methods are forwarding all of
  # their arguments (positional, keyword, and block) on to the request method.
  # The ArgsForward node appears in both the caller (the request method calls)
  # and the callee (the get and post definitions).
  class ArgsForward < Node
    # [String] the value of the operator
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_args_forward(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # ArrayLiteral represents an array literal, which can optionally contain
  # elements.
  #
  #     []
  #     [one, two, three]
  #
  class ArrayLiteral < Node
    class QWordsFormatter
      # [Args] the contents of the array
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def format(q)
        q.group(0, "%w[", "]") do
          q.indent do
            q.breakable("")
            q.seplist(contents.parts, -> { q.breakable }) do |part|
              if part.is_a?(StringLiteral)
                q.format(part.parts.first)
              else
                q.text(part.value[1..-1])
              end
            end
          end
          q.breakable("")
        end
      end
    end

    class QSymbolsFormatter
      # [Args] the contents of the array
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def format(q)
        q.group(0, "%i[", "]") do
          q.indent do
            q.breakable("")
            q.seplist(contents.parts, -> { q.breakable }) do |part|
              q.format(part.value)
            end
          end
          q.breakable("")
        end
      end
    end

    class VarRefsFormatter
      # [Args] the contents of the array
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def format(q)
        q.group(0, "[", "]") do
          q.indent do
            q.breakable("")

            separator = -> do
              q.text(",")
              q.fill_breakable
            end

            q.seplist(contents.parts, separator) { |part| q.format(part) }
          end
          q.breakable("")
        end
      end
    end

    class EmptyWithCommentsFormatter
      # [LBracket] the opening bracket
      attr_reader :lbracket

      def initialize(lbracket)
        @lbracket = lbracket
      end

      def format(q)
        q.group do
          q.text("[")
          q.indent do
            lbracket.comments.each do |comment|
              q.breakable(force: true)
              comment.format(q)
            end
          end
          q.breakable(force: true)
          q.text("]")
        end
      end
    end

    # [LBracket] the bracket that opens this array
    attr_reader :lbracket

    # [nil | Args] the contents of the array
    attr_reader :contents

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbracket:, contents:, location:, comments: [])
      @lbracket = lbracket
      @contents = contents
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_array(self)
    end

    def child_nodes
      [lbracket, contents]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        lbracket: lbracket,
        contents: contents,
        location: location,
        comments: comments
      }
    end

    def format(q)
      if qwords?
        QWordsFormatter.new(contents).format(q)
        return
      end

      if qsymbols?
        QSymbolsFormatter.new(contents).format(q)
        return
      end

      if var_refs?(q)
        VarRefsFormatter.new(contents).format(q)
        return
      end

      if empty_with_comments?
        EmptyWithCommentsFormatter.new(lbracket).format(q)
        return
      end

      q.group do
        q.format(lbracket)

        if contents
          q.indent do
            q.breakable("")
            q.format(contents)
          end
        end

        q.breakable("")
        q.text("]")
      end
    end

    private

    def qwords?
      lbracket.comments.empty? && contents && contents.comments.empty? &&
        contents.parts.length > 1 &&
        contents.parts.all? do |part|
          case part
          when StringLiteral
            part.comments.empty? && part.parts.length == 1 &&
              part.parts.first.is_a?(TStringContent) &&
              !part.parts.first.value.match?(/[\s\[\]\\]/)
          when CHAR
            !part.value.match?(/[\[\]\\]/)
          else
            false
          end
        end
    end

    def qsymbols?
      lbracket.comments.empty? && contents && contents.comments.empty? &&
        contents.parts.length > 1 &&
        contents.parts.all? do |part|
          part.is_a?(SymbolLiteral) && part.comments.empty?
        end
    end

    def var_refs?(q)
      lbracket.comments.empty? && contents && contents.comments.empty? &&
        contents.parts.all? do |part|
          part.is_a?(VarRef) && part.comments.empty?
        end &&
        (
          contents.parts.sum { |part| part.value.value.length + 2 } >
            q.maxwidth * 2
        )
    end

    # If we have an empty array that contains only comments, then we're going
    # to do some special printing to ensure they get indented correctly.
    def empty_with_comments?
      contents.nil? && lbracket.comments.any? && lbracket.comments.none?(&:inline?)
    end
  end

  # AryPtn represents matching against an array pattern using the Ruby 2.7+
  # pattern matching syntax. It’s one of the more complicated nodes, because
  # the four parameters that it accepts can almost all be nil.
  #
  #     case [1, 2, 3]
  #     in [Integer, Integer]
  #       "matched"
  #     in Container[Integer, Integer]
  #       "matched"
  #     in [Integer, *, Integer]
  #       "matched"
  #     end
  #
  # An AryPtn node is created with four parameters: an optional constant
  # wrapper, an array of positional matches, an optional splat with identifier,
  # and an optional array of positional matches that occur after the splat.
  # All of the in clauses above would create an AryPtn node.
  class AryPtn < Node
    class RestFormatter
      # [VarField] the identifier that represents the remaining positionals
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def comments
        value.comments
      end

      def format(q)
        q.text("*")
        q.format(value)
      end
    end

    # [nil | VarRef] the optional constant wrapper
    attr_reader :constant

    # [Array[ untyped ]] the regular positional arguments that this array
    # pattern is matching against
    attr_reader :requireds

    # [nil | VarField] the optional starred identifier that grabs up a list of
    # positional arguments
    attr_reader :rest

    # [Array[ untyped ]] the list of positional arguments occurring after the
    # optional star if there is one
    attr_reader :posts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      constant:,
      requireds:,
      rest:,
      posts:,
      location:,
      comments: []
    )
      @constant = constant
      @requireds = requireds
      @rest = rest
      @posts = posts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_aryptn(self)
    end

    def child_nodes
      [constant, *requireds, rest, *posts]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        constant: constant,
        requireds: requireds,
        rest: rest,
        posts: posts,
        location: location,
        comments: comments
      }
    end

    def format(q)
      parts = [*requireds]
      parts << RestFormatter.new(rest) if rest
      parts += posts

      if constant
        q.group do
          q.format(constant)
          q.text("[")
          q.seplist(parts) { |part| q.format(part) }
          q.text("]")
        end

        return
      end

      parent = q.parent
      if parts.length == 1 || PATTERNS.include?(parent.class)
        q.text("[")
        q.seplist(parts) { |part| q.format(part) }
        q.text("]")
      else
        q.group { q.seplist(parts) { |part| q.format(part) } }
      end
    end
  end

  # Determins if the following value should be indented or not.
  module AssignFormatting
    def self.skip_indent?(value)
      case value
      in ArrayLiteral | HashLiteral | Heredoc | Lambda | QSymbols | QWords | Symbols | Words
        true
      in Call[receiver:]
        skip_indent?(receiver)
      in DynaSymbol[quote:]
        quote.start_with?("%s")
      else
        false
      end
    end
  end

  # Assign represents assigning something to a variable or constant. Generally,
  # the left side of the assignment is going to be any node that ends with the
  # name "Field".
  #
  #     variable = value
  #
  class Assign < Node
    # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
    # to assign the result of the expression to
    attr_reader :target

    # [untyped] the expression to be assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, value:, location:, comments: [])
      @target = target
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_assign(self)
    end

    def child_nodes
      [target, value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { target: target, value: value, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.format(target)
        q.text(" =")

        if skip_indent?
          q.text(" ")
          q.format(value)
        else
          q.indent do
            q.breakable
            q.format(value)
          end
        end
      end
    end

    private

    def skip_indent?
      target.comments.empty? &&
        (target.is_a?(ARefField) || AssignFormatting.skip_indent?(value))
    end
  end

  # Assoc represents a key-value pair within a hash. It is a child node of
  # either an AssocListFromArgs or a BareAssocHash.
  #
  #     { key1: value1, key2: value2 }
  #
  # In the above example, the would be two AssocNew nodes.
  class Assoc < Node
    # [untyped] the key of this pair
    attr_reader :key

    # [untyped] the value of this pair
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(key:, value:, location:, comments: [])
      @key = key
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_assoc(self)
    end

    def child_nodes
      [key, value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { key: key, value: value, location: location, comments: comments }
    end

    def format(q)
      if value&.is_a?(HashLiteral)
        format_contents(q)
      else
        q.group { format_contents(q) }
      end
    end

    private

    def format_contents(q)
      q.parent.format_key(q, key)
      return unless value

      if key.comments.empty? && AssignFormatting.skip_indent?(value)
        q.text(" ")
        q.format(value)
      else
        q.indent do
          q.breakable
          q.format(value)
        end
      end
    end
  end

  # AssocSplat represents double-splatting a value into a hash (either a hash
  # literal or a bare hash in a method call).
  #
  #     { **pairs }
  #
  class AssocSplat < Node
    # [untyped] the expression that is being splatted
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_assoc_splat(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("**")
      q.format(value)
    end
  end

  # Backref represents a global variable referencing a matched value. It comes
  # in the form of a $ followed by a positive integer.
  #
  #     $1
  #
  class Backref < Node
    # [String] the name of the global backreference variable
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_backref(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # Backtick represents the use of the ` operator. It's usually found being used
  # for an XStringLiteral, but could also be found as the name of a method being
  # defined.
  class Backtick < Node
    # [String] the backtick in the string
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_backtick(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # This module is responsible for formatting the assocs contained within a
  # hash or bare hash. It first determines if every key in the hash can use
  # labels. If it can, it uses labels. Otherwise it uses hash rockets.
  module HashKeyFormatter
    class Labels
      def format_key(q, key)
        case key
        when Label
          q.format(key)
        when SymbolLiteral
          q.format(key.value)
          q.text(":")
        when DynaSymbol
          q.format(key)
          q.text(":")
        end
      end
    end

    class Rockets
      def format_key(q, key)
        case key
        when Label
          q.text(":")
          q.text(key.value.chomp(":"))
        when DynaSymbol
          q.text(":")
          q.format(key)
        else
          q.format(key)
        end

        q.text(" =>")
      end
    end

    def self.for(container)
      labels =
        container.assocs.all? do |assoc|
          next true if assoc.is_a?(AssocSplat)

          case assoc.key
          when Label
            true
          when SymbolLiteral
            # When attempting to convert a hash rocket into a hash label,
            # you need to take care because only certain patterns are
            # allowed. Ruby source says that they have to match keyword
            # arguments to methods, but don't specify what that is. After
            # some experimentation, it looks like it's:
            value = assoc.key.value.value
            value.match?(/^[_A-Za-z]/) && !value.end_with?("=")
          when DynaSymbol
            true
          else
            false
          end
        end

      (labels ? Labels : Rockets).new
    end
  end

  # BareAssocHash represents a hash of contents being passed as a method
  # argument (and therefore has omitted braces). It's very similar to an
  # AssocListFromArgs node.
  #
  #     method(key1: value1, key2: value2)
  #
  class BareAssocHash < Node
    # [Array[ Assoc | AssocSplat ]]
    attr_reader :assocs

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(assocs:, location:, comments: [])
      @assocs = assocs
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_bare_assoc_hash(self)
    end

    def child_nodes
      assocs
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { assocs: assocs, location: location, comments: comments }
    end

    def format(q)
      q.seplist(assocs) { |assoc| q.format(assoc) }
    end

    def format_key(q, key)
      (@key_formatter ||= HashKeyFormatter.for(self)).format_key(q, key)
    end
  end

  # Begin represents a begin..end chain.
  #
  #     begin
  #       value
  #     end
  #
  class Begin < Node
    # [BodyStmt] the bodystmt that contains the contents of this begin block
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(bodystmt:, location:, comments: [])
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_begin(self)
    end

    def child_nodes
      [bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { bodystmt: bodystmt, location: location, comments: comments }
    end

    def format(q)
      q.text("begin")

      unless bodystmt.empty?
        q.indent do
          q.breakable(force: true) unless bodystmt.statements.empty?
          q.format(bodystmt)
        end
      end

      q.breakable(force: true)
      q.text("end")
    end
  end

  # PinnedBegin represents a pinning a nested statement within pattern matching.
  #
  #     case value
  #     in ^(statement)
  #     end
  #
  class PinnedBegin < Node
    # [untyped] the expression being pinned
    attr_reader :statement

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, location:, comments: [])
      @statement = statement
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_pinned_begin(self)
    end

    def child_nodes
      [statement]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { statement: statement, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("^(")
        q.nest(1) do
          q.indent do
            q.breakable("")
            q.format(statement)
          end
          q.breakable("")
          q.text(")")
        end
      end
    end
  end

  # Binary represents any expression that involves two sub-expressions with an
  # operator in between. This can be something that looks like a mathematical
  # operation:
  #
  #     1 + 1
  #
  # but can also be something like pushing a value onto an array:
  #
  #     array << value
  #
  class Binary < Node
    # [untyped] the left-hand side of the expression
    attr_reader :left

    # [Symbol] the operator used between the two expressions
    attr_reader :operator

    # [untyped] the right-hand side of the expression
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, operator:, right:, location:, comments: [])
      @left = left
      @operator = operator
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_binary(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        left: left,
        operator: operator,
        right: right,
        location: location,
        comments: comments
      }
    end

    def format(q)
      power = operator == :**

      q.group do
        q.group { q.format(left) }
        q.text(" ") unless power

        if operator == :<<
          q.text(operator.to_s)
          q.text(" ")
          q.format(right)
        else
          q.group do
            q.text(operator.to_s)

            q.indent do
              q.breakable(power ? "" : " ")
              q.format(right)
            end
          end
        end
      end
    end
  end

  # This module will remove any breakables from the list of contents so that no
  # newlines are present in the output.
  module RemoveBreaks
    class << self
      def call(doc)
        marker = Object.new
        stack = [doc]

        while stack.any?
          doc = stack.pop

          if doc == marker
            stack.pop
            next
          end

          stack += [doc, marker]

          case doc
          when PrettyPrint::Align, PrettyPrint::Indent, PrettyPrint::Group
            doc.contents.map! { |child| remove_breaks(child) }
            stack += doc.contents.reverse
          when PrettyPrint::IfBreak
            doc.flat_contents.map! { |child| remove_breaks(child) }
            stack += doc.flat_contents.reverse
          end
        end
      end

      private

      def remove_breaks(doc)
        case doc
        when PrettyPrint::Breakable
          text = PrettyPrint::Text.new
          text.add(object: doc.force? ? "; " : doc.separator, width: doc.width)
          text
        when PrettyPrint::IfBreak
          PrettyPrint::Align.new(indent: 0, contents: doc.flat_contents)
        else
          doc
        end
      end
    end
  end

  # BlockVar represents the parameters being declared for a block. Effectively
  # this node is everything contained within the pipes. This includes all of the
  # various parameter types, as well as block-local variable declarations.
  #
  #     method do |positional, optional = value, keyword:, &block; local|
  #     end
  #
  class BlockVar < Node
    # [Params] the parameters being declared with the block
    attr_reader :params

    # [Array[ Ident ]] the list of block-local variable declarations
    attr_reader :locals

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(params:, locals:, location:, comments: [])
      @params = params
      @locals = locals
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_block_var(self)
    end

    def child_nodes
      [params, *locals]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { params: params, locals: locals, location: location, comments: comments }
    end

    def format(q)
      q.group(0, "|", "|") do
        doc = q.format(params)
        RemoveBreaks.call(doc)

        if locals.any?
          q.text("; ")
          q.seplist(locals, -> { q.text(", ") }) { |local| q.format(local) }
        end
      end
    end
  end

  # BlockArg represents declaring a block parameter on a method definition.
  #
  #     def method(&block); end
  #
  class BlockArg < Node
    # [nil | Ident] the name of the block argument
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(name:, location:, comments: [])
      @name = name
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_blockarg(self)
    end

    def child_nodes
      [name]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("&")
      q.format(name) if name
    end
  end

  # bodystmt can't actually determine its bounds appropriately because it
  # doesn't necessarily know where it started. So the parent node needs to
  # report back down into this one where it goes.
  class BodyStmt < Node
    # [Statements] the list of statements inside the begin clause
    attr_reader :statements

    # [nil | Rescue] the optional rescue chain attached to the begin clause
    attr_reader :rescue_clause

    # [nil | Kw] the optional else keyword
    attr_reader :else_keyword

    # [nil | Statements] the optional set of statements inside the else clause
    attr_reader :else_clause

    # [nil | Ensure] the optional ensure clause
    attr_reader :ensure_clause

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      statements:,
      rescue_clause:,
      else_keyword:,
      else_clause:,
      ensure_clause:,
      location:,
      comments: []
    )
      @statements = statements
      @rescue_clause = rescue_clause
      @else_keyword = else_keyword
      @else_clause = else_clause
      @ensure_clause = ensure_clause
      @location = location
      @comments = comments
    end

    def bind(start_char, start_column, end_char, end_column)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          start_column: start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )

      parts = [rescue_clause, else_clause, ensure_clause]

      # Here we're going to determine the bounds for the statements
      consequent = parts.compact.first
      statements.bind(
        start_char,
        start_column,
        consequent ? consequent.location.start_char : end_char,
        consequent ? consequent.location.start_column : end_column
      )

      # Next we're going to determine the rescue clause if there is one
      if rescue_clause
        consequent = parts.drop(1).compact.first
        rescue_clause.bind_end(
          consequent ? consequent.location.start_char : end_char,
          consequent ? consequent.location.start_column : end_column
        )
      end
    end

    def empty?
      statements.empty? && !rescue_clause && !else_clause && !ensure_clause
    end

    def accept(visitor)
      visitor.visit_bodystmt(self)
    end

    def child_nodes
      [statements, rescue_clause, else_keyword, else_clause, ensure_clause]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statements: statements,
        rescue_clause: rescue_clause,
        else_clause: else_clause,
        ensure_clause: ensure_clause,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(statements) unless statements.empty?

        if rescue_clause
          q.nest(-2) do
            q.breakable(force: true)
            q.format(rescue_clause)
          end
        end

        if else_clause
          q.nest(-2) do
            q.breakable(force: true)
            q.format(else_keyword)
          end

          unless else_clause.empty?
            q.breakable(force: true)
            q.format(else_clause)
          end
        end

        if ensure_clause
          q.nest(-2) do
            q.breakable(force: true)
            q.format(ensure_clause)
          end
        end
      end
    end
  end

  # Responsible for formatting either a BraceBlock or a DoBlock.
  class BlockFormatter
    class BlockOpenFormatter
      # [String] the actual output that should be printed
      attr_reader :text

      # [LBrace | Keyword] the node that is being represented
      attr_reader :node

      def initialize(text, node)
        @text = text
        @node = node
      end

      def comments
        node.comments
      end

      def format(q)
        q.text(text)
      end
    end

    # [BraceBlock | DoBlock] the block node to be formatted
    attr_reader :node

    # [LBrace | Keyword] the node that opens the block
    attr_reader :block_open

    # [String] the string that closes the block
    attr_reader :block_close

    # [BodyStmt | Statements] the statements inside the block
    attr_reader :statements

    def initialize(node, block_open, block_close, statements)
      @node = node
      @block_open = block_open
      @block_close = block_close
      @statements = statements
    end

    def format(q)
      # If this is nested anywhere inside of a Command or CommandCall node, then
      # we can't change which operators we're using for the bounds of the block.
      break_opening, break_closing, flat_opening, flat_closing =
        if unchangeable_bounds?(q)
          [block_open.value, block_close, block_open.value, block_close]
        elsif forced_do_end_bounds?(q)
          %w[do end do end]
        elsif forced_brace_bounds?(q)
          %w[{ } { }]
        else
          %w[do end { }]
        end

      # If the receiver of this block a Command or CommandCall node, then there
      # are no parentheses around the arguments to that command, so we need to
      # break the block.
      receiver = q.parent.call
      if receiver.is_a?(Command) || receiver.is_a?(CommandCall)
        q.break_parent
        format_break(q, break_opening, break_closing)
        return
      end

      q.group do
        q.if_break { format_break(q, break_opening, break_closing) }.if_flat do
          format_flat(q, flat_opening, flat_closing)
        end
      end
    end

    private

    # If this is nested anywhere inside certain nodes, then we can't change
    # which operators/keywords we're using for the bounds of the block.
    def unchangeable_bounds?(q)
      q.parents.any? do |parent|
        # If we hit a statements, then we're safe to use whatever since we
        # know for certain we're going to get split over multiple lines
        # anyway.
        break false if parent.is_a?(Statements)

        [Command, CommandCall].include?(parent.class)
      end
    end

    # If we're a sibling of a control-flow keyword, then we're going to have to
    # use the do..end bounds.
    def forced_do_end_bounds?(q)
      [Break, Next, Return, Super].include?(q.parent.call.class)
    end

    # If we're the predicate of a loop or conditional, then we're going to have
    # to go with the {..} bounds.
    def forced_brace_bounds?(q)
      parents = q.parents.to_a
      parents.each_with_index.any? do |parent, index|
        # If we hit certain breakpoints then we know we're safe.
        break false if [Paren, Statements].include?(parent.class)

        [
          If,
          IfMod,
          IfOp,
          Unless,
          UnlessMod,
          While,
          WhileMod,
          Until,
          UntilMod
        ].include?(parent.class) && parent.predicate == parents[index - 1]
      end
    end

    def format_break(q, opening, closing)
      q.text(" ")
      q.format(BlockOpenFormatter.new(opening, block_open), stackable: false)

      if node.block_var
        q.text(" ")
        q.format(node.block_var)
      end

      unless statements.empty?
        q.indent do
          q.breakable
          q.format(statements)
        end
      end

      q.breakable
      q.text(closing)
    end

    def format_flat(q, opening, closing)
      q.text(" ")
      q.format(BlockOpenFormatter.new(opening, block_open), stackable: false)

      if node.block_var
        q.breakable
        q.format(node.block_var)
        q.breakable
      end

      if statements.empty?
        q.text(" ") if opening == "do"
      else
        q.breakable unless node.block_var
        q.format(statements)
        q.breakable
      end

      q.text(closing)
    end
  end

  # BraceBlock represents passing a block to a method call using the { }
  # operators.
  #
  #     method { |variable| variable + 1 }
  #
  class BraceBlock < Node
    # [LBrace] the left brace that opens this block
    attr_reader :lbrace

    # [nil | BlockVar] the optional set of parameters to the block
    attr_reader :block_var

    # [Statements] the list of expressions to evaluate within the block
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbrace:, block_var:, statements:, location:, comments: [])
      @lbrace = lbrace
      @block_var = block_var
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_brace_block(self)
    end

    def child_nodes
      [lbrace, block_var, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        lbrace: lbrace,
        block_var: block_var,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      BlockFormatter.new(self, lbrace, "}", statements).format(q)
    end
  end

  # Formats either a Break, Next, or Return node.
  class FlowControlFormatter
    # [String] the keyword to print
    attr_reader :keyword

    # [Break | Next | Return] the node being formatted
    attr_reader :node

    def initialize(keyword, node)
      @keyword = keyword
      @node = node
    end

    def format(q)
      q.group do
        q.text(keyword)

        case node.arguments.parts
        in []
          # Here there are no arguments at all, so we're not going to print
          # anything. This would be like if we had:
          #
          #     break
          #
        in [Paren[contents: { body: [ArrayLiteral[contents: { parts: [_, _, *] }] => array] }]]
          # Here we have a single argument that is a set of parentheses wrapping
          # an array literal that has at least 2 elements. We're going to print
          # the contents of the array directly. This would be like if we had:
          #
          #     break([1, 2, 3])
          #
          # which we will print as:
          #
          #     break 1, 2, 3
          #
          q.text(" ")
          format_array_contents(q, array)
        in [Paren[contents: { body: [ArrayLiteral => statement] }]]
          # Here we have a single argument that is a set of parentheses wrapping
          # an array literal that has 0 or 1 elements. We're going to skip the
          # parentheses but print the array itself. This would be like if we
          # had:
          #
          #     break([1])
          #
          # which we will print as:
          #
          #     break [1]
          #
          q.text(" ")
          q.format(statement)
        in [Paren[contents: { body: [statement] }]] if skip_parens?(statement)
          # Here we have a single argument that is a set of parentheses that
          # themselves contain a single statement. That statement is a simple
          # value that we can skip the parentheses for. This would be like if we
          # had:
          #
          #     break(1)
          #
          # which we will print as:
          #
          #     break 1
          #
          q.text(" ")
          q.format(statement)
        in [Paren => part]
          # Here we have a single argument that is a set of parentheses. We're
          # going to print the parentheses themselves as if they were the set of
          # arguments. This would be like if we had:
          #
          #     break(foo.bar)
          #
          q.format(part)
        in [ArrayLiteral[contents: { parts: [_, _, *] }] => array]
          # Here there is a single argument that is an array literal with at
          # least two elements. We skip directly into the array literal's
          # elements in order to print the contents. This would be like if we
          # had:
          #
          #     break [1, 2, 3]
          #
          # which we will print as:
          #
          #     break 1, 2, 3
          #
          q.text(" ")
          format_array_contents(q, array)
        in [ArrayLiteral => part]
          # Here there is a single argument that is an array literal with 0 or 1
          # elements. In this case we're going to print the array as it is
          # because skipping the brackets would change the remaining. This would
          # be like if we had:
          #
          #     break []
          #     break [1]
          #
          q.text(" ")
          q.format(part)
        in [_]
          # Here there is a single argument that hasn't matched one of our
          # previous cases. We're going to print the argument as it is. This
          # would be like if we had:
          #
          #     break foo
          #
          format_arguments(q, "(", ")")
        else
          # If there are multiple arguments, format them all. If the line is
          # going to break into multiple, then use brackets to start and end the
          # expression.
          format_arguments(q, " [", "]")
        end
      end
    end

    private

    def format_array_contents(q, array)
      q.if_break { q.text("[") }
      q.indent do
        q.breakable("")
        q.format(array.contents)
      end
      q.breakable("")
      q.if_break { q.text("]") }
    end

    def format_arguments(q, opening, closing)
      q.if_break { q.text(opening) }
      q.indent do
        q.breakable(" ")
        q.format(node.arguments)
      end
      q.breakable("")
      q.if_break { q.text(closing) }
    end

    def skip_parens?(node)
      case node
      in FloatLiteral | Imaginary | Int | RationalLiteral
        true
      in VarRef[value: Const | CVar | GVar | IVar | Kw]
        true
      else
        false
      end
    end
  end

  # Break represents using the +break+ keyword.
  #
  #     break
  #
  # It can also optionally accept arguments, as in:
  #
  #     break 1
  #
  class Break < Node
    # [Args] the arguments being sent to the keyword
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_break(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("break", self).format(q)
    end
  end

  # Wraps a call operator (which can be a string literal :: or an Op node or a
  # Period node) and formats it when called.
  class CallOperatorFormatter
    # [:"::" | Op | Period] the operator being formatted
    attr_reader :operator

    def initialize(operator)
      @operator = operator
    end

    def comments
      operator == :"::" ? [] : operator.comments
    end

    def format(q)
      if operator == :"::" || (operator.is_a?(Op) && operator.value == "::")
        q.text(".")
      else
        operator.format(q)
      end
    end
  end

  class CallChainFormatter
    # [Call | MethodAddBlock] the top of the call chain
    attr_reader :node

    def initialize(node)
      @node = node
    end

    def format(q)
      children = [node]
      threshold = 3

      # First, walk down the chain until we get to the point where we're not
      # longer at a chainable node.
      while true
        case children.last
        in Call[receiver: Call]
          children << children.last.receiver
        in Call[receiver: MethodAddBlock[call: Call]]
          children << children.last.receiver
        in MethodAddBlock[call: Call]
          children << children.last.call
        else
          break
        end
      end

      # Here, we have very specialized behavior where if we're within a sig
      # block, then we're going to assume we're creating a Sorbet type
      # signature. In that case, we really want the threshold to be lowered so
      # that we create method chains off of any two method calls within the
      # block. For more details, see
      # https://github.com/prettier/plugin-ruby/issues/863.
      parents = q.parents.take(4)
      if parent = parents[2]
        # If we're at a do_block, then we want to go one more level up. This is
        # because do blocks have BodyStmt nodes instead of just Statements
        # nodes.
        parent = parents[3] if parent.is_a?(DoBlock)

        case parent
        in MethodAddBlock[call: FCall[value: { value: "sig" }]]
          threshold = 2
        else
        end
      end

      if children.length >= threshold
        q.group { q.if_break { format_chain(q, children) }.if_flat { node.format_contents(q) } }
      else
        node.format_contents(q)
      end
    end

    def format_chain(q, children)
      # We're going to have some specialized behavior for if it's an entire
      # chain of calls without arguments except for the last one. This is common
      # enough in Ruby source code that it's worth the extra complexity here.
      empty_except_last =
        children.drop(1).all? do |child|
          child.is_a?(Call) && child.arguments.nil?
        end

      # Here, we're going to add all of the children onto the stack of the
      # formatter so it's as if we had descending normally into them. This is
      # necessary so they can check their parents as normal.
      q.stack.concat(children)
      q.format(children.last.receiver)

      q.group do
        if attach_directly?(children.last)
          format_child(q, children.pop)
          q.stack.pop
        end

        q.indent do
          # We track another variable that checks if you need to move the
          # operator to the previous line in case there are trailing comments
          # and a trailing operator.
          skip_operator = false

          while child = children.pop
            case child
            in Call[receiver: Call[message: { value: "where" }], message: { value: "not" }]
              # This is very specialized behavior wherein we group
              # .where.not calls together because it looks better. For more
              # information, see
              # https://github.com/prettier/plugin-ruby/issues/862.
            in Call
              # If we're at a Call node and not a MethodAddBlock node in the
              # chain then we're going to add a newline so it indents properly.
              q.breakable("")
            else
            end

            format_child(
              q,
              child,
              skip_comments: children.empty?,
              skip_operator: skip_operator,
              skip_attached: empty_except_last && children.empty?
            )

            # If the parent call node has a comment on the message then we need
            # to print the operator trailing in order to keep it working.
            case children.last
            in Call[message: { comments: [_, *] }, operator:]
              q.format(CallOperatorFormatter.new(operator))
              skip_operator = true
            else
              skip_operator = false
            end

            # Pop off the formatter's stack so that it aligns with what would
            # have happened if we had been formatting normally.
            q.stack.pop
          end
        end
      end

      if empty_except_last
        case node
        in Call
          node.format_arguments(q)
        in MethodAddBlock[block:]
          q.format(block)
        end
      end
    end

    def self.chained?(node)
      case node
      in Call | MethodAddBlock[call: Call]
        true
      else
        false
      end
    end

    private

    # For certain nodes, we want to attach directly to the end and don't
    # want to indent the first call. So we'll pop off the first children and
    # format it separately here.
    def attach_directly?(node)
      [ArrayLiteral, HashLiteral, Heredoc, If, Unless, XStringLiteral]
        .include?(node.receiver.class)
    end

    def format_child(q, child, skip_comments: false, skip_operator: false, skip_attached: false)
      # First, format the actual contents of the child.
      case child
      in Call
        q.group do
          q.format(CallOperatorFormatter.new(child.operator)) unless skip_operator
          q.format(child.message) if child.message != :call
          child.format_arguments(q) unless skip_attached
        end
      in MethodAddBlock
        q.format(child.block) unless skip_attached
      end

      # If there are any comments on this node then we need to explicitly print
      # them out here since we're bypassing the normal comment printing.
      if child.comments.any? && !skip_comments
        child.comments.each do |comment|
          comment.inline? ? q.text(" ") : q.breakable
          comment.format(q)
        end

        q.break_parent
      end
    end
  end

  # Call represents a method call.
  #
  #     receiver.message
  #
  class Call < Node
    # [untyped] the receiver of the method call
    attr_reader :receiver

    # [:"::" | Op | Period] the operator being used to send the message
    attr_reader :operator

    # [:call | Backtick | Const | Ident | Op] the message being sent
    attr_reader :message

    # [nil | ArgParen | Args] the arguments to the method call
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      receiver:,
      operator:,
      message:,
      arguments:,
      location:,
      comments: []
    )
      @receiver = receiver
      @operator = operator
      @message = message
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_call(self)
    end

    def child_nodes
      [
        receiver,
        (operator if operator != :"::"),
        (message if message != :call),
        arguments
      ]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        location: location,
        comments: comments
      }
    end

    def format(q)
      # If we're at the top of a call chain, then we're going to do some
      # specialized printing in case we can print it nicely. We _only_ do this
      # at the top of the chain to avoid weird recursion issues.
      if !CallChainFormatter.chained?(q.parent) && CallChainFormatter.chained?(receiver)
        q.group { q.if_break { CallChainFormatter.new(self).format(q) }.if_flat { format_contents(q) } }
      else
        format_contents(q)
      end
    end

    def format_arguments(q)
      case arguments
      in ArgParen
        q.format(arguments)
      in Args
        q.text(" ")
        q.format(arguments)
      else
        # Do nothing if there are no arguments.
      end
    end

    def format_contents(q)
      call_operator = CallOperatorFormatter.new(operator)

      q.group do
        q.format(receiver)

        # If there are trailing comments on the call operator, then we need to
        # use the trailing form as opposed to the leading form.
        q.format(call_operator) if call_operator.comments.any?

        q.group do
          q.indent do
            if receiver.comments.any? || call_operator.comments.any?
              q.breakable(force: true)
            end

            if call_operator.comments.empty?
              q.format(call_operator, stackable: false)
            end

            q.format(message) if message != :call
          end

          format_arguments(q)
        end
      end
    end
  end

  # Case represents the beginning of a case chain.
  #
  #     case value
  #     when 1
  #       "one"
  #     when 2
  #       "two"
  #     else
  #       "number"
  #     end
  #
  class Case < Node
    # [Kw] the keyword that opens this expression
    attr_reader :keyword

    # [nil | untyped] optional value being switched on
    attr_reader :value

    # [In | When] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, value:, consequent:, location:, comments: [])
      @keyword = keyword
      @value = value
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_case(self)
    end

    def child_nodes
      [keyword, value, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        keyword: keyword,
        value: value,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(keyword)

        if value
          q.text(" ")
          q.format(value)
        end

        q.breakable(force: true)
        q.format(consequent)
        q.breakable(force: true)

        q.text("end")
      end
    end
  end

  # RAssign represents a single-line pattern match.
  #
  #     value in pattern
  #     value => pattern
  #
  class RAssign < Node
    # [untyped] the left-hand expression
    attr_reader :value

    # [Kw | Op] the operator being used to match against the pattern, which is
    # either => or in
    attr_reader :operator

    # [untyped] the pattern on the right-hand side of the expression
    attr_reader :pattern

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, operator:, pattern:, location:, comments: [])
      @value = value
      @operator = operator
      @pattern = pattern
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_rassign(self)
    end

    def child_nodes
      [value, operator, pattern]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        value: value,
        operator: operator,
        pattern: pattern,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(value)
        q.text(" ")
        q.format(operator)
        q.group do
          q.indent do
            q.breakable
            q.format(pattern)
          end
        end
      end
    end
  end

  # Class represents defining a class using the +class+ keyword.
  #
  #     class Container
  #     end
  #
  # Classes can have path names as their class name in case it's being nested
  # under a namespace, as in:
  #
  #     class Namespace::Container
  #     end
  #
  # Classes can also be defined as a top-level path, in the case that it's
  # already in a namespace but you want to define it at the top-level instead,
  # as in:
  #
  #     module OtherNamespace
  #       class ::Namespace::Container
  #       end
  #     end
  #
  # All of these declarations can also have an optional superclass reference, as
  # in:
  #
  #     class Child < Parent
  #     end
  #
  # That superclass can actually be any Ruby expression, it doesn't necessarily
  # need to be a constant, as in:
  #
  #     class Child < method
  #     end
  #
  class ClassDeclaration < Node
    # [ConstPathRef | ConstRef | TopConstRef] the name of the class being
    # defined
    attr_reader :constant

    # [nil | untyped] the optional superclass declaration
    attr_reader :superclass

    # [BodyStmt] the expressions to execute within the context of the class
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, superclass:, bodystmt:, location:, comments: [])
      @constant = constant
      @superclass = superclass
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_class(self)
    end

    def child_nodes
      [constant, superclass, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        constant: constant,
        superclass: superclass,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      declaration = -> do
        q.group do
          q.text("class ")
          q.format(constant)

          if superclass
            q.text(" < ")
            q.format(superclass)
          end
        end
      end

      if bodystmt.empty?
        q.group do
          declaration.call
          q.breakable(force: true)
          q.text("end")
        end
      else
        q.group do
          declaration.call

          q.indent do
            q.breakable(force: true)
            q.format(bodystmt)
          end

          q.breakable(force: true)
          q.text("end")
        end
      end
    end
  end

  # Comma represents the use of the , operator.
  class Comma < Node
    # [String] the comma in the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_comma(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # Command represents a method call with arguments and no parentheses. Note
  # that Command nodes only happen when there is no explicit receiver for this
  # method.
  #
  #     method argument
  #
  class Command < Node
    # [Const | Ident] the message being sent to the implicit receiver
    attr_reader :message

    # [Args] the arguments being sent with the message
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(message:, arguments:, location:, comments: [])
      @message = message
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_command(self)
    end

    def child_nodes
      [message, arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        message: message,
        arguments: arguments,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(message)
        align(q, self) { q.format(arguments) }
      end
    end

    private

    def align(q, node, &block)
      case node.arguments
      in Args[parts: [Def | Defs | DefEndless]]
        q.text(" ")
        yield
      in Args[parts: [IfOp]]
        q.if_flat { q.text(" ") }
        yield
      in Args[parts: [Command => command]]
        align(q, command, &block)
      else
        q.text(" ")
        q.nest(message.value.length + 1) { yield }
      end
    end
  end

  # CommandCall represents a method call on an object with arguments and no
  # parentheses.
  #
  #     object.method argument
  #
  class CommandCall < Node
    # [untyped] the receiver of the message
    attr_reader :receiver

    # [:"::" | Op | Period] the operator used to send the message
    attr_reader :operator

    # [Const | Ident | Op] the message being send
    attr_reader :message

    # [nil | Args] the arguments going along with the message
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      receiver:,
      operator:,
      message:,
      arguments:,
      location:,
      comments: []
    )
      @receiver = receiver
      @operator = operator
      @message = message
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_command_call(self)
    end

    def child_nodes
      [receiver, message, arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        doc =
          q.nest(0) do
            q.format(receiver)
            q.format(CallOperatorFormatter.new(operator), stackable: false)
            q.format(message)
          end

        case arguments
        in Args[parts: [IfOp]]
          q.if_flat { q.text(" ") }
          q.format(arguments)
        in Args
          q.text(" ")
          q.nest(argument_alignment(q, doc)) { q.format(arguments) }
        else
          # If there are no arguments, print nothing.
        end
      end
    end

    private

    # This is a somewhat naive method that is attempting to sum up the width of
    # the doc nodes that make up the given doc node. This is used to align
    # content.
    def doc_width(parent)
      queue = [parent]
      width = 0

      until queue.empty?
        doc = queue.shift

        case doc
        when PrettyPrint::Text
          width += doc.width
        when PrettyPrint::Indent, PrettyPrint::Align, PrettyPrint::Group
          queue = doc.contents + queue
        when PrettyPrint::IfBreak
          queue = doc.break_contents + queue
        when PrettyPrint::Breakable
          width = 0
        end
      end

      width
    end

    def argument_alignment(q, doc)
      # Very special handling case for rspec matchers. In general with rspec
      # matchers you expect to see something like:
      #
      #     expect(foo).to receive(:bar).with(
      #       'one',
      #       'two',
      #       'three',
      #       'four',
      #       'five'
      #     )
      #
      # In this case the arguments are aligned to the left side as opposed to
      # being aligned with the `receive` call.
      if %w[to not_to to_not].include?(message.value)
        0
      else
        width = doc_width(doc) + 1
        width > (q.maxwidth / 2) ? 0 : width
      end
    end
  end

  # Comment represents a comment in the source.
  #
  #     # comment
  #
  class Comment < Node
    # [String] the contents of the comment
    attr_reader :value

    # [boolean] whether or not there is code on the same line as this comment.
    # If there is, then inline will be true.
    attr_reader :inline
    alias inline? inline

    def initialize(value:, inline:, location:)
      @value = value
      @inline = inline
      @location = location

      @leading = false
      @trailing = false
    end

    def leading!
      @leading = true
    end

    def leading?
      @leading
    end

    def trailing!
      @trailing = true
    end

    def trailing?
      @trailing
    end

    def ignore?
      value[1..-1].strip == "stree-ignore"
    end

    def comments
      []
    end

    def accept(visitor)
      visitor.visit_comment(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, inline: inline, location: location }
    end

    def format(q)
      q.text(value)
    end
  end

  # Const represents a literal value that _looks_ like a constant. This could
  # actually be a reference to a constant:
  #
  #     Constant
  #
  # It could also be something that looks like a constant in another context, as
  # in a method call to a capitalized method:
  #
  #     object.Constant
  #
  # or a symbol that starts with a capital letter:
  #
  #     :Constant
  #
  class Const < Node
    # [String] the name of the constant
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_const(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # ConstPathField represents the child node of some kind of assignment. It
  # represents when you're assigning to a constant that is being referenced as
  # a child of another variable.
  #
  #     object::Const = value
  #
  class ConstPathField < Node
    # [untyped] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, constant:, location:, comments: [])
      @parent = parent
      @constant = constant
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_const_path_field(self)
    end

    def child_nodes
      [parent, constant]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        parent: parent,
        constant: constant,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(parent)
      q.text("::")
      q.format(constant)
    end
  end

  # ConstPathRef represents referencing a constant by a path.
  #
  #     object::Const
  #
  class ConstPathRef < Node
    # [untyped] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, constant:, location:, comments: [])
      @parent = parent
      @constant = constant
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_const_path_ref(self)
    end

    def child_nodes
      [parent, constant]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        parent: parent,
        constant: constant,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(parent)
      q.text("::")
      q.format(constant)
    end
  end

  # ConstRef represents the name of the constant being used in a class or module
  # declaration.
  #
  #     class Container
  #     end
  #
  class ConstRef < Node
    # [Const] the constant itself
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, location:, comments: [])
      @constant = constant
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_const_ref(self)
    end

    def child_nodes
      [constant]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.format(constant)
    end
  end

  # CVar represents the use of a class variable.
  #
  #     @@variable
  #
  class CVar < Node
    # [String] the name of the class variable
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_cvar(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # Def represents defining a regular method on the current self object.
  #
  #     def method(param) result end
  #
  class Def < Node
    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [Params | Paren] the parameter declaration for the method
    attr_reader :params

    # [BodyStmt] the expressions to be executed by the method
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(name:, params:, bodystmt:, location:, comments: [])
      @name = name
      @params = params
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_def(self)
    end

    def child_nodes
      [name, params, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        name: name,
        params: params,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.group do
          q.text("def ")
          q.format(name)

          if !params.is_a?(Params) || !params.empty? || params.comments.any?
            q.format(params)
          end
        end

        unless bodystmt.empty?
          q.indent do
            q.breakable(force: true)
            q.format(bodystmt)
          end
        end

        q.breakable(force: true)
        q.text("end")
      end
    end
  end

  # DefEndless represents defining a single-line method since Ruby 3.0+.
  #
  #     def method = result
  #
  class DefEndless < Node
    # [untyped] the target where the method is being defined
    attr_reader :target

    # [Op | Period] the operator being used to declare the method
    attr_reader :operator

    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [nil | Params | Paren] the parameter declaration for the method
    attr_reader :paren

    # [untyped] the expression to be executed by the method
    attr_reader :statement

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      target:,
      operator:,
      name:,
      paren:,
      statement:,
      location:,
      comments: []
    )
      @target = target
      @operator = operator
      @name = name
      @paren = paren
      @statement = statement
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_def_endless(self)
    end

    def child_nodes
      [target, operator, name, paren, statement]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        target: target,
        operator: operator,
        name: name,
        paren: paren,
        statement: statement,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.text("def ")

        if target
          q.format(target)
          q.format(CallOperatorFormatter.new(operator), stackable: false)
        end

        q.format(name)

        if paren
          params = paren
          params = params.contents if params.is_a?(Paren)
          q.format(paren) unless params.empty?
        end

        q.text(" =")
        q.group do
          q.indent do
            q.breakable
            q.format(statement)
          end
        end
      end
    end
  end

  # Defined represents the use of the +defined?+ operator. It can be used with
  # and without parentheses.
  #
  #     defined?(variable)
  #
  class Defined < Node
    # [untyped] the value being sent to the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_defined(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.group(0, "defined?(", ")") do
        q.indent do
          q.breakable("")
          q.format(value)
        end
        q.breakable("")
      end
    end
  end

  # Defs represents defining a singleton method on an object.
  #
  #     def object.method(param) result end
  #
  class Defs < Node
    # [untyped] the target where the method is being defined
    attr_reader :target

    # [Op | Period] the operator being used to declare the method
    attr_reader :operator

    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [Params | Paren] the parameter declaration for the method
    attr_reader :params

    # [BodyStmt] the expressions to be executed by the method
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      target:,
      operator:,
      name:,
      params:,
      bodystmt:,
      location:,
      comments: []
    )
      @target = target
      @operator = operator
      @name = name
      @params = params
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_defs(self)
    end

    def child_nodes
      [target, operator, name, params, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        target: target,
        operator: operator,
        name: name,
        params: params,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.group do
          q.text("def ")
          q.format(target)
          q.format(CallOperatorFormatter.new(operator), stackable: false)
          q.format(name)

          if !params.is_a?(Params) || !params.empty? || params.comments.any?
            q.format(params)
          end
        end

        unless bodystmt.empty?
          q.indent do
            q.breakable(force: true)
            q.format(bodystmt)
          end
        end

        q.breakable(force: true)
        q.text("end")
      end
    end
  end

  # DoBlock represents passing a block to a method call using the +do+ and +end+
  # keywords.
  #
  #     method do |value|
  #     end
  #
  class DoBlock < Node
    # [Kw] the do keyword that opens this block
    attr_reader :keyword

    # [nil | BlockVar] the optional variable declaration within this block
    attr_reader :block_var

    # [BodyStmt] the expressions to be executed within this block
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, block_var:, bodystmt:, location:, comments: [])
      @keyword = keyword
      @block_var = block_var
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_do_block(self)
    end

    def child_nodes
      [keyword, block_var, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        keyword: keyword,
        block_var: block_var,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      BlockFormatter.new(self, keyword, "end", bodystmt).format(q)
    end
  end

  # Responsible for formatting Dot2 and Dot3 nodes.
  class DotFormatter
    # [String] the operator to display
    attr_reader :operator

    # [Dot2 | Dot3] the node that is being formatter
    attr_reader :node

    def initialize(operator, node)
      @operator = operator
      @node = node
    end

    def format(q)
      space = [If, IfMod, Unless, UnlessMod].include?(q.parent.class)

      left = node.left
      right = node.right

      q.format(left) if left
      q.text(" ") if space
      q.text(operator)
      q.text(" ") if space
      q.format(right) if right
    end
  end

  # Dot2 represents using the .. operator between two expressions. Usually this
  # is to create a range object.
  #
  #     1..2
  #
  # Sometimes this operator is used to create a flip-flop.
  #
  #     if value == 5 .. value == 10
  #     end
  #
  # One of the sides of the expression may be nil, but not both.
  class Dot2 < Node
    # [nil | untyped] the left side of the expression
    attr_reader :left

    # [nil | untyped] the right side of the expression
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:, comments: [])
      @left = left
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_dot2(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { left: left, right: right, location: location, comments: comments }
    end

    def format(q)
      DotFormatter.new("..", self).format(q)
    end
  end

  # Dot3 represents using the ... operator between two expressions. Usually this
  # is to create a range object. It's effectively the same event as the Dot2
  # node but with this operator you're asking Ruby to omit the final value.
  #
  #     1...2
  #
  # Like Dot2 it can also be used to create a flip-flop.
  #
  #     if value == 5 ... value == 10
  #     end
  #
  # One of the sides of the expression may be nil, but not both.
  class Dot3 < Node
    # [nil | untyped] the left side of the expression
    attr_reader :left

    # [nil | untyped] the right side of the expression
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:, comments: [])
      @left = left
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_dot3(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { left: left, right: right, location: location, comments: comments }
    end

    def format(q)
      DotFormatter.new("...", self).format(q)
    end
  end

  # Responsible for providing information about quotes to be used for strings
  # and dynamic symbols.
  module Quotes
    # The matching pairs of quotes that can be used with % literals.
    PAIRS = { "(" => ")", "[" => "]", "{" => "}", "<" => ">" }.freeze

    # If there is some part of this string that matches an escape sequence or
    # that contains the interpolation pattern ("#{"), then we are locked into
    # whichever quote the user chose. (If they chose single quotes, then double
    # quoting would activate the escape sequence, and if they chose double
    # quotes, then single quotes would deactivate it.)
    def self.locked?(node)
      node.parts.any? do |part|
        part.is_a?(TStringContent) && part.value.match?(/#[@${]|[\\]/)
      end
    end

    # Find the matching closing quote for the given opening quote.
    def self.matching(quote)
      PAIRS.fetch(quote) { quote }
    end

    # Escape and unescape single and double quotes as needed to be able to
    # enclose +content+ with +enclosing+.
    def self.normalize(content, enclosing)
      return content if enclosing != "\"" && enclosing != "'"

      content.gsub(/\\([\s\S])|(['"])/) do
        _match, escaped, quote = Regexp.last_match.to_a

        if quote == enclosing
          "\\#{quote}"
        elsif quote
          quote
        else
          "\\#{escaped}"
        end
      end
    end
  end

  # DynaSymbol represents a symbol literal that uses quotes to dynamically
  # define its value.
  #
  #     :"#{variable}"
  #
  # They can also be used as a special kind of dynamic hash key, as in:
  #
  #     { "#{key}": value }
  #
  class DynaSymbol < Node
    # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
    # dynamic symbol
    attr_reader :parts

    # [String] the quote used to delimit the dynamic symbol
    attr_reader :quote

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, quote:, location:, comments: [])
      @parts = parts
      @quote = quote
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_dyna_symbol(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, quote: quote, location: location, comments: comments }
    end

    def format(q)
      opening_quote, closing_quote = quotes(q)

      q.group(0, opening_quote, closing_quote) do
        parts.each do |part|
          if part.is_a?(TStringContent)
            value = Quotes.normalize(part.value, closing_quote)
            separator = -> { q.breakable(force: true, indent: false) }
            q.seplist(value.split(/\r?\n/, -1), separator) do |text|
              q.text(text)
            end
          else
            q.format(part)
          end
        end
      end
    end

    private

    # Here we determine the quotes to use for a dynamic symbol. It's bound by a
    # lot of rules because it could be in many different contexts with many
    # different kinds of escaping.
    def quotes(q)
      # If we're inside of an assoc node as the key, then it will handle
      # printing the : on its own since it could change sides.
      parent = q.parent
      hash_key = parent.is_a?(Assoc) && parent.key == self

      if quote.start_with?("%s")
        # Here we're going to check if there is a closing character, a new line,
        # or a quote in the content of the dyna symbol. If there is, then
        # quoting could get weird, so just bail out and stick to the original
        # quotes in the source.
        matching = Quotes.matching(quote[2])
        pattern = /[\n#{Regexp.escape(matching)}'"]/

        if parts.any? { |part|
             part.is_a?(TStringContent) && part.value.match?(pattern)
           }
          [quote, matching]
        elsif Quotes.locked?(self)
          ["#{":" unless hash_key}'", "'"]
        else
          ["#{":" unless hash_key}#{q.quote}", q.quote]
        end
      elsif Quotes.locked?(self)
        if quote.start_with?(":")
          [hash_key ? quote[1..-1] : quote, quote[1..-1]]
        else
          [hash_key ? quote : ":#{quote}", quote]
        end
      else
        [hash_key ? q.quote : ":#{q.quote}", q.quote]
      end
    end
  end

  # Else represents the end of an +if+, +unless+, or +case+ chain.
  #
  #     if variable
  #     else
  #     end
  #
  class Else < Node
    # [Kw] the else keyword
    attr_reader :keyword

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, statements:, location:, comments: [])
      @keyword = keyword
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_else(self)
    end

    def child_nodes
      [keyword, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        keyword: keyword,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(keyword)

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end
      end
    end
  end

  # Elsif represents another clause in an +if+ or +unless+ chain.
  #
  #     if variable
  #     elsif other_variable
  #     end
  #
  class Elsif < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Elsif | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      predicate:,
      statements:,
      consequent:,
      location:,
      comments: []
    )
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_elsif(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.group do
          q.text("elsif ")
          q.nest("elsif".length - 1) { q.format(predicate) }
        end

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end

        if consequent
          q.group do
            q.breakable(force: true)
            q.format(consequent)
          end
        end
      end
    end
  end

  # EmbDoc represents a multi-line comment.
  #
  #     =begin
  #     first line
  #     second line
  #     =end
  #
  class EmbDoc < Node
    # [String] the contents of the comment
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def inline?
      false
    end

    def ignore?
      false
    end

    def comments
      []
    end

    def accept(visitor)
      visitor.visit_embdoc(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end

    def format(q)
      q.trim
      q.text(value)
    end
  end

  # EmbExprBeg represents the beginning token for using interpolation inside of
  # a parent node that accepts string content (like a string or regular
  # expression).
  #
  #     "Hello, #{person}!"
  #
  class EmbExprBeg < Node
    # [String] the #{ used in the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_embexpr_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # EmbExprEnd represents the ending token for using interpolation inside of a
  # parent node that accepts string content (like a string or regular
  # expression).
  #
  #     "Hello, #{person}!"
  #
  class EmbExprEnd < Node
    # [String] the } used in the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_embexpr_end(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # EmbVar represents the use of shorthand interpolation for an instance, class,
  # or global variable into a parent node that accepts string content (like a
  # string or regular expression).
  #
  #     "#@variable"
  #
  # In the example above, an EmbVar node represents the # because it forces
  # @variable to be interpolated.
  class EmbVar < Node
    # [String] the # used in the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_embvar(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # Ensure represents the use of the +ensure+ keyword and its subsequent
  # statements.
  #
  #     begin
  #     ensure
  #     end
  #
  class Ensure < Node
    # [Kw] the ensure keyword that began this node
    attr_reader :keyword

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, statements:, location:, comments: [])
      @keyword = keyword
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_ensure(self)
    end

    def child_nodes
      [keyword, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        keyword: keyword,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(keyword)

      unless statements.empty?
        q.indent do
          q.breakable(force: true)
          q.format(statements)
        end
      end
    end
  end

  # ExcessedComma represents a trailing comma in a list of block parameters. It
  # changes the block parameters such that they will destructure.
  #
  #     [[1, 2, 3], [2, 3, 4]].each do |first, second,|
  #     end
  #
  # In the above example, an ExcessedComma node would appear in the third
  # position of the Params node that is used to declare that block. The third
  # position typically represents a rest-type parameter, but in this case is
  # used to indicate that a trailing comma was used.
  class ExcessedComma < Node
    # [String] the comma
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_excessed_comma(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # FCall represents the piece of a method call that comes before any arguments
  # (i.e., just the name of the method). It is used in places where the parser
  # is sure that it is a method call and not potentially a local variable.
  #
  #     method(argument)
  #
  # In the above example, it's referring to the +method+ segment.
  class FCall < Node
    # [Const | Ident] the name of the method
    attr_reader :value

    # [nil | ArgParen | Args] the arguments to the method call
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, arguments:, location:, comments: [])
      @value = value
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_fcall(self)
    end

    def child_nodes
      [value, arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        value: value,
        arguments: arguments,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(value)

      if arguments.is_a?(ArgParen) && arguments.arguments.nil? && !value.is_a?(Const)
        # If you're using an explicit set of parentheses on something that looks
        # like a constant, then we need to match that in order to maintain valid
        # Ruby. For example, you could do something like Foo(), on which we
        # would need to keep the parentheses to make it look like a method call.
      else
        q.format(arguments)
      end
    end
  end

  # Field is always the child of an assignment. It represents assigning to a
  # “field” on an object.
  #
  #     object.variable = value
  #
  class Field < Node
    # [untyped] the parent object that owns the field being assigned
    attr_reader :parent

    # [:"::" | Op | Period] the operator being used for the assignment
    attr_reader :operator

    # [Const | Ident] the name of the field being assigned
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, operator:, name:, location:, comments: [])
      @parent = parent
      @operator = operator
      @name = name
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_field(self)
    end

    def child_nodes
      [parent, (operator if operator != :"::"), name]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        parent: parent,
        operator: operator,
        name: name,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(parent)
        q.format(CallOperatorFormatter.new(operator), stackable: false)
        q.format(name)
      end
    end
  end

  # FloatLiteral represents a floating point number literal.
  #
  #     1.0
  #
  class FloatLiteral < Node
    # [String] the value of the floating point number literal
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_float(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # FndPtn represents matching against a pattern where you find a pattern in an
  # array using the Ruby 3.0+ pattern matching syntax.
  #
  #     case value
  #     in [*, 7, *]
  #     end
  #
  class FndPtn < Node
    # [nil | untyped] the optional constant wrapper
    attr_reader :constant

    # [VarField] the splat on the left-hand side
    attr_reader :left

    # [Array[ untyped ]] the list of positional expressions in the pattern that
    # are being matched
    attr_reader :values

    # [VarField] the splat on the right-hand side
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, left:, values:, right:, location:, comments: [])
      @constant = constant
      @left = left
      @values = values
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_fndptn(self)
    end

    def child_nodes
      [constant, left, *values, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        constant: constant,
        left: left,
        values: values,
        right: right,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(constant) if constant
      q.group(0, "[", "]") do
        q.text("*")
        q.format(left)
        q.comma_breakable

        q.seplist(values) { |value| q.format(value) }
        q.comma_breakable

        q.text("*")
        q.format(right)
      end
    end
  end

  # For represents using a +for+ loop.
  #
  #     for value in list do
  #     end
  #
  class For < Node
    # [MLHS | VarField] the variable declaration being used to
    # pull values out of the object being enumerated
    attr_reader :index

    # [untyped] the object being enumerated in the loop
    attr_reader :collection

    # [Statements] the statements to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(index:, collection:, statements:, location:, comments: [])
      @index = index
      @collection = collection
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_for(self)
    end

    def child_nodes
      [index, collection, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        index: index,
        collection: collection,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.text("for ")
        q.group { q.format(index) }
        q.text(" in ")
        q.format(collection)

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end

        q.breakable(force: true)
        q.text("end")
      end
    end
  end

  # GVar represents a global variable literal.
  #
  #     $variable
  #
  class GVar < Node
    # [String] the name of the global variable
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_gvar(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # HashLiteral represents a hash literal.
  #
  #     { key => value }
  #
  class HashLiteral < Node
    class EmptyWithCommentsFormatter
      # [LBrace] the opening brace
      attr_reader :lbrace

      def initialize(lbrace)
        @lbrace = lbrace
      end

      def format(q)
        q.group do
          q.text("{")
          q.indent do
            lbrace.comments.each do |comment|
              q.breakable(force: true)
              comment.format(q)
            end
          end
          q.breakable(force: true)
          q.text("}")
        end
      end
    end

    # [LBrace] the left brace that opens this hash
    attr_reader :lbrace

    # [Array[ AssocNew | AssocSplat ]] the optional contents of the hash
    attr_reader :assocs

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbrace:, assocs:, location:, comments: [])
      @lbrace = lbrace
      @assocs = assocs
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_hash(self)
    end

    def child_nodes
      [lbrace] + assocs
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { lbrace: lbrace, assocs: assocs, location: location, comments: comments }
    end

    def format(q)
      if q.parent.is_a?(Assoc)
        format_contents(q)
      else
        q.group { format_contents(q) }
      end
    end

    def format_key(q, key)
      (@key_formatter ||= HashKeyFormatter.for(self)).format_key(q, key)
    end

    private

    # If we have an empty hash that contains only comments, then we're going
    # to do some special printing to ensure they get indented correctly.
    def empty_with_comments?
      assocs.empty? && lbrace.comments.any? && lbrace.comments.none?(&:inline?)
    end

    def format_contents(q)
      if empty_with_comments?
        EmptyWithCommentsFormatter.new(lbrace).format(q)
        return
      end

      q.format(lbrace)

      if assocs.empty?
        q.breakable("")
      else
        q.indent do
          q.breakable
          q.seplist(assocs) { |assoc| q.format(assoc) }
        end
        q.breakable
      end

      q.text("}")
    end
  end

  # Heredoc represents a heredoc string literal.
  #
  #     <<~DOC
  #       contents
  #     DOC
  #
  class Heredoc < Node
    # [HeredocBeg] the opening of the heredoc
    attr_reader :beginning

    # [String] the ending of the heredoc
    attr_reader :ending

    # [Integer] how far to dedent the heredoc
    attr_reader :dedent

    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # heredoc string literal
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, ending: nil, dedent: 0, parts: [], location:, comments: [])
      @beginning = beginning
      @ending = ending
      @dedent = dedent
      @parts = parts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_heredoc(self)
    end

    def child_nodes
      [beginning, *parts]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        location: location,
        ending: ending,
        parts: parts,
        comments: comments
      }
    end

    def format(q)
      # This is a very specific behavior that should probably be included in the
      # prettyprint module. It's when you want to force a newline, but don't
      # want to force the break parent.
      breakable = -> do
        q.target <<
          PrettyPrint::Breakable.new(" ", 1, indent: false, force: true)
      end

      q.group do
        q.format(beginning)

        q.line_suffix(priority: Formatter::HEREDOC_PRIORITY) do
          q.group do
            breakable.call

            parts.each do |part|
              if part.is_a?(TStringContent)
                texts = part.value.split(/\r?\n/, -1)
                q.seplist(texts, breakable) { |text| q.text(text) }
              else
                q.format(part)
              end
            end

            q.text(ending)
          end
        end
      end
    end
  end

  # HeredocBeg represents the beginning declaration of a heredoc.
  #
  #     <<~DOC
  #       contents
  #     DOC
  #
  # In the example above the HeredocBeg node represents <<~DOC.
  class HeredocBeg < Node
    # [String] the opening declaration of the heredoc
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_heredoc_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # HshPtn represents matching against a hash pattern using the Ruby 2.7+
  # pattern matching syntax.
  #
  #     case value
  #     in { key: }
  #     end
  #
  class HshPtn < Node
    class KeywordFormatter
      # [Label] the keyword being used
      attr_reader :key

      # [untyped] the optional value for the keyword
      attr_reader :value

      def initialize(key, value)
        @key = key
        @value = value
      end

      def comments
        []
      end

      def format(q)
        q.format(key)

        if value
          q.text(" ")
          q.format(value)
        end
      end
    end

    class KeywordRestFormatter
      # [VarField] the parameter that matches the remaining keywords
      attr_reader :keyword_rest

      def initialize(keyword_rest)
        @keyword_rest = keyword_rest
      end

      def comments
        []
      end

      def format(q)
        q.text("**")
        q.format(keyword_rest)
      end
    end

    # [nil | untyped] the optional constant wrapper
    attr_reader :constant

    # [Array[ [Label, untyped] ]] the set of tuples representing the keywords
    # that should be matched against in the pattern
    attr_reader :keywords

    # [nil | VarField] an optional parameter to gather up all remaining keywords
    attr_reader :keyword_rest

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, keywords:, keyword_rest:, location:, comments: [])
      @constant = constant
      @keywords = keywords
      @keyword_rest = keyword_rest
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_hshptn(self)
    end

    def child_nodes
      [constant, *keywords.flatten(1), keyword_rest]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        constant: constant,
        keywords: keywords,
        keyword_rest: keyword_rest,
        location: location,
        comments: comments
      }
    end

    def format(q)
      parts = keywords.map { |(key, value)| KeywordFormatter.new(key, value) }
      parts << KeywordRestFormatter.new(keyword_rest) if keyword_rest

      contents = -> do
        q.group { q.seplist(parts) { |part| q.format(part, stackable: false) } }

        # If there isn't a constant, and there's a blank keyword_rest, then we
        # have an plain ** that needs to have a `then` after it in order to
        # parse correctly on the next parse.
        q.text(" then") if !constant && keyword_rest && keyword_rest.value.nil?
      end

      if constant
        q.format(constant)
        q.group(0, "[", "]", &contents)
        return
      end

      if parts.empty?
        q.text("{}")
      elsif PATTERNS.include?(q.parent.class)
        q.text("{ ")
        contents.call
        q.text(" }")
      else
        contents.call
      end
    end
  end

  # The list of nodes that represent patterns inside of pattern matching so that
  # when a pattern is being printed it knows if it's nested.
  PATTERNS = [AryPtn, Binary, FndPtn, HshPtn, RAssign]

  # Ident represents an identifier anywhere in code. It can represent a very
  # large number of things, depending on where it is in the syntax tree.
  #
  #     value
  #
  class Ident < Node
    # [String] the value of the identifier
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_ident(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # If the predicate of a conditional or loop contains an assignment (in which
  # case we can't know for certain that that assignment doesn't impact the
  # statements inside the conditional) then we can't use the modifier form
  # and we must use the block form.
  module ContainsAssignment
    def self.call(parent)
      queue = [parent]

      while node = queue.shift
        return true if [Assign, MAssign, OpAssign].include?(node.class)
        queue += node.child_nodes
      end

      false
    end
  end

  # In order for an `if` or `unless` expression to be shortened to a ternary,
  # there has to be one and only one consequent clause which is an Else. Both
  # the body of the main node and the body of the Else node must have only one
  # statement, and that statement must not be on the denied list of potential
  # statements.
  module Ternaryable
    class << self
      def call(q, node)
        case q.parents.take(2)[1]
        in Paren[contents: Statements[body: [node]]]
          # If this is a conditional inside of a parentheses as the only
          # content, then we don't want to transform it into a ternary.
          # Presumably the user wanted it to be an explicit conditional because
          # there are parentheses around it. So we'll just leave it in place.
          false
        else
          # Otherwise, we're going to check the conditional for certain cases.
          case node
          in { predicate: Assign | Command | CommandCall | MAssign | OpAssign }
            false
          in { statements: { body: [truthy] }, consequent: Else[statements: { body: [falsy] }] }
            ternaryable?(truthy) && ternaryable?(falsy)
          else
            false
          end
        end
      end

      private

      # Certain expressions cannot be reduced to a ternary without adding
      # parentheses around them. In this case we say they cannot be ternaried and
      # default instead to breaking them into multiple lines.
      def ternaryable?(statement)
        # This is a list of nodes that should not be allowed to be a part of a
        # ternary clause.
        no_ternary = [
          Alias, Assign, Break, Command, CommandCall, Heredoc, If, IfMod, IfOp,
          Lambda, MAssign, Next, OpAssign, RescueMod, Return, Return0, Super,
          Undef, Unless, UnlessMod, Until, UntilMod, VarAlias, VoidStmt, While,
          WhileMod, Yield, Yield0, ZSuper
        ]

        # Here we're going to check that the only statement inside the
        # statements node is no a part of our denied list of nodes that can be
        # ternaries.
        #
        # If the user is using one of the lower precedence "and" or "or"
        # operators, then we can't use a ternary expression as it would break
        # the flow control.
        !no_ternary.include?(statement.class) &&
          !(statement.is_a?(Binary) && %i[and or].include?(statement.operator))
      end
    end
  end

  # Formats an If or Unless node.
  class ConditionalFormatter
    # [String] the keyword associated with this conditional
    attr_reader :keyword

    # [If | Unless] the node that is being formatted
    attr_reader :node

    def initialize(keyword, node)
      @keyword = keyword
      @node = node
    end

    def format(q)
      # If we can transform this node into a ternary, then we're going to print
      # a special version that uses the ternary operator if it fits on one line.
      if Ternaryable.call(q, node)
        format_ternary(q)
        return
      end

      # If the predicate of the conditional contains an assignment (in which
      # case we can't know for certain that that assignment doesn't impact the
      # statements inside the conditional) then we can't use the modifier form
      # and we must use the block form.
      if ContainsAssignment.call(node.predicate)
        format_break(q, force: true)
        return
      end

      if node.consequent || node.statements.empty? || contains_conditional?
        q.group { format_break(q, force: true) }
      else
        q.group do
          q.if_break { format_break(q, force: false) }.if_flat do
            Parentheses.flat(q) do
              q.format(node.statements)
              q.text(" #{keyword} ")
              q.format(node.predicate)
            end
          end
        end
      end
    end

    private

    def format_break(q, force:)
      q.text("#{keyword} ")
      q.nest(keyword.length + 1) { q.format(node.predicate) }

      unless node.statements.empty?
        q.indent do
          q.breakable(force: force)
          q.format(node.statements)
        end
      end

      if node.consequent
        q.breakable(force: force)
        q.format(node.consequent)
      end

      q.breakable(force: force)
      q.text("end")
    end

    def format_ternary(q)
      q.group do
        q.if_break do
          q.text("#{keyword} ")
          q.nest(keyword.length + 1) { q.format(node.predicate) }

          q.indent do
            q.breakable
            q.format(node.statements)
          end

          q.breakable
          q.group do
            q.format(node.consequent.keyword)
            q.indent do
              # This is a very special case of breakable where we want to force
              # it into the output but we _don't_ want to explicitly break the
              # parent. If a break-parent shows up in the tree, then it's going
              # to force it all the way up to the tree, which is going to negate
              # the ternary. Maybe this should be an option in prettyprint? As
              # in force: :no_break_parent or something.
              q.target << PrettyPrint::Breakable.new(" ", 1, force: true)
              q.format(node.consequent.statements)
            end
          end

          q.breakable
          q.text("end")
        end.if_flat do
          Parentheses.flat(q) do
            q.format(node.predicate)
            q.text(" ? ")

            statements = [node.statements, node.consequent.statements]
            statements.reverse! if keyword == "unless"

            q.format(statements[0])
            q.text(" : ")
            q.format(statements[1])
          end
        end
      end
    end

    def contains_conditional?
      case node
      in { statements: { body: [If | IfMod | IfOp | Unless | UnlessMod] } }
        true
      else
        false
      end
    end
  end

  # If represents the first clause in an +if+ chain.
  #
  #     if predicate
  #     end
  #
  class If < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil, Elsif, Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      predicate:,
      statements:,
      consequent:,
      location:,
      comments: []
    )
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_if(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      ConditionalFormatter.new("if", self).format(q)
    end
  end

  # IfOp represents a ternary clause.
  #
  #     predicate ? truthy : falsy
  #
  class IfOp < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [untyped] the expression to be executed if the predicate is truthy
    attr_reader :truthy

    # [untyped] the expression to be executed if the predicate is falsy
    attr_reader :falsy

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, truthy:, falsy:, location:, comments: [])
      @predicate = predicate
      @truthy = truthy
      @falsy = falsy
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_if_op(self)
    end

    def child_nodes
      [predicate, truthy, falsy]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        truthy: truthy,
        falsy: falsy,
        location: location,
        comments: comments
      }
    end

    def format(q)
      force_flat = [
        Alias, Assign, Break, Command, CommandCall, Heredoc, If, IfMod, IfOp,
        Lambda, MAssign, Next, OpAssign, RescueMod, Return, Return0, Super,
        Undef, Unless, UnlessMod, UntilMod, VarAlias, VoidStmt, WhileMod, Yield,
        Yield0, ZSuper
      ]

      if q.parent.is_a?(Paren) || force_flat.include?(truthy.class) || force_flat.include?(falsy.class)
        q.group { format_flat(q) }
        return
      end

      q.group { q.if_break { format_break(q) }.if_flat { format_flat(q) } }
    end

    private

    def format_break(q)
      Parentheses.break(q) do
        q.text("if ")
        q.nest("if ".length) { q.format(predicate) }

        q.indent do
          q.breakable
          q.format(truthy)
        end

        q.breakable
        q.text("else")

        q.indent do
          q.breakable
          q.format(falsy)
        end

        q.breakable
        q.text("end")
      end
    end

    def format_flat(q)
      q.format(predicate)
      q.text(" ?")

      q.breakable
      q.format(truthy)
      q.text(" :")

      q.breakable
      q.format(falsy)
    end
  end

  # Formats an IfMod or UnlessMod node.
  class ConditionalModFormatter
    # [String] the keyword associated with this conditional
    attr_reader :keyword

    # [IfMod | UnlessMod] the node that is being formatted
    attr_reader :node

    def initialize(keyword, node)
      @keyword = keyword
      @node = node
    end

    def format(q)
      if ContainsAssignment.call(node.statement) || q.parent.is_a?(In)
        q.group { format_flat(q) }
      else
        q.group { q.if_break { format_break(q) }.if_flat { format_flat(q) } }
      end
    end

    private

    def format_break(q)
      q.text("#{keyword} ")
      q.nest(keyword.length + 1) { q.format(node.predicate) }
      q.indent do
        q.breakable
        q.format(node.statement)
      end
      q.breakable
      q.text("end")
    end

    def format_flat(q)
      Parentheses.flat(q) do
        q.format(node.statement)
        q.text(" #{keyword} ")
        q.format(node.predicate)
      end
    end
  end

  # IfMod represents the modifier form of an +if+ statement.
  #
  #     expression if predicate
  #
  class IfMod < Node
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, predicate:, location:, comments: [])
      @statement = statement
      @predicate = predicate
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_if_mod(self)
    end

    def child_nodes
      [statement, predicate]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        predicate: predicate,
        location: location,
        comments: comments
      }
    end

    def format(q)
      ConditionalModFormatter.new("if", self).format(q)
    end
  end

  # Imaginary represents an imaginary number literal.
  #
  #     1i
  #
  class Imaginary < Node
    # [String] the value of the imaginary number literal
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_imaginary(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # In represents using the +in+ keyword within the Ruby 2.7+ pattern matching
  # syntax.
  #
  #     case value
  #     in pattern
  #     end
  #
  class In < Node
    # [untyped] the pattern to check against
    attr_reader :pattern

    # [Statements] the expressions to execute if the pattern matched
    attr_reader :statements

    # [nil | In | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(pattern:, statements:, consequent:, location:, comments: [])
      @pattern = pattern
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_in(self)
    end

    def child_nodes
      [pattern, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        pattern: pattern,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      keyword = "in "

      q.group do
        q.text(keyword)
        q.nest(keyword.length) { q.format(pattern) }

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end

        if consequent
          q.breakable(force: true)
          q.format(consequent)
        end
      end
    end
  end

  # Int represents an integer number literal.
  #
  #     1
  #
  class Int < Node
    # [String] the value of the integer
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_int(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      if !value.start_with?(/\+?0/) && value.length >= 5 && !value.include?("_")
        # If it's a plain integer and it doesn't have any underscores separating
        # the values, then we're going to insert them every 3 characters
        # starting from the right.
        index = (value.length + 2) % 3
        q.text("  #{value}"[index..-1].scan(/.../).join("_").strip)
      else
        q.text(value)
      end
    end
  end

  # IVar represents an instance variable literal.
  #
  #     @variable
  #
  class IVar < Node
    # [String] the name of the instance variable
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_ivar(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # Kw represents the use of a keyword. It can be almost anywhere in the syntax
  # tree, so you end up seeing it quite a lot.
  #
  #     if value
  #     end
  #
  # In the above example, there would be two Kw nodes: one for the if and one
  # for the end. Note that anything that matches the list of keywords in Ruby
  # will use a Kw, so if you use a keyword in a symbol literal for instance:
  #
  #     :if
  #
  # then the contents of the symbol node will contain a Kw node.
  class Kw < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_kw(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # KwRestParam represents defining a parameter in a method definition that
  # accepts all remaining keyword parameters.
  #
  #     def method(**kwargs) end
  #
  class KwRestParam < Node
    # [nil | Ident] the name of the parameter
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(name:, location:, comments: [])
      @name = name
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_kwrest_param(self)
    end

    def child_nodes
      [name]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("**")
      q.format(name) if name
    end
  end

  # Label represents the use of an identifier to associate with an object. You
  # can find it in a hash key, as in:
  #
  #     { key: value }
  #
  # In this case "key:" would be the body of the label. You can also find it in
  # pattern matching, as in:
  #
  #     case value
  #     in key:
  #     end
  #
  # In this case "key:" would be the body of the label.
  class Label < Node
    # [String] the value of the label
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_label(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # LabelEnd represents the end of a dynamic symbol.
  #
  #     { "key": value }
  #
  # In the example above, LabelEnd represents the "\":" token at the end of the
  # hash key. This node is important for determining the type of quote being
  # used by the label.
  class LabelEnd < Node
    # [String] the end of the label
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_label_end(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # Lambda represents using a lambda literal (not the lambda method call).
  #
  #     ->(value) { value * 2 }
  #
  class Lambda < Node
    # [Params | Paren] the parameter declaration for this lambda
    attr_reader :params

    # [BodyStmt | Statements] the expressions to be executed in this lambda
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(params:, statements:, location:, comments: [])
      @params = params
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_lambda(self)
    end

    def child_nodes
      [params, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        params: params,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group(0, "->") do
        if params.is_a?(Paren)
          q.format(params) unless params.contents.empty?
        elsif !params.empty?
          q.group do
            q.text("(")
            q.format(params)
            q.text(")")
          end
        end

        q.text(" ")
        q.if_break do
          force_parens =
            q.parents.any? do |node|
              node.is_a?(Command) || node.is_a?(CommandCall)
            end

          q.text(force_parens ? "{" : "do")
          q.indent do
            q.breakable
            q.format(statements)
          end

          q.breakable
          q.text(force_parens ? "}" : "end")
        end.if_flat do
          q.text("{ ")
          q.format(statements)
          q.text(" }")
        end
      end
    end
  end

  # LBrace represents the use of a left brace, i.e., {.
  class LBrace < Node
    # [String] the left brace
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_lbrace(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # LBracket represents the use of a left bracket, i.e., [.
  class LBracket < Node
    # [String] the left bracket
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_lbracket(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # LParen represents the use of a left parenthesis, i.e., (.
  class LParen < Node
    # [String] the left parenthesis
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_lparen(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # MAssign is a parent node of any kind of multiple assignment. This includes
  # splitting out variables on the left like:
  #
  #     first, second, third = value
  #
  # as well as splitting out variables on the right, as in:
  #
  #     value = first, second, third
  #
  # Both sides support splats, as well as variables following them. There's also
  # destructuring behavior that you can achieve with the following:
  #
  #     first, = value
  #
  class MAssign < Node
    # [MLHS | MLHSParen] the target of the multiple assignment
    attr_reader :target

    # [untyped] the value being assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, value:, location:, comments: [])
      @target = target
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_massign(self)
    end

    def child_nodes
      [target, value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { target: target, value: value, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.group { q.format(target) }
        q.text(" =")
        q.indent do
          q.breakable
          q.format(value)
        end
      end
    end
  end

  # MethodAddBlock represents a method call with a block argument.
  #
  #     method {}
  #
  class MethodAddBlock < Node
    # [Call | Command | CommandCall | FCall] the method call
    attr_reader :call

    # [BraceBlock | DoBlock] the block being sent with the method call
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(call:, block:, location:, comments: [])
      @call = call
      @block = block
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_method_add_block(self)
    end

    def child_nodes
      [call, block]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { call: call, block: block, location: location, comments: comments }
    end

    def format(q)
      # If we're at the top of a call chain, then we're going to do some
      # specialized printing in case we can print it nicely. We _only_ do this
      # at the top of the chain to avoid weird recursion issues.
      if !CallChainFormatter.chained?(q.parent) && CallChainFormatter.chained?(call)
        q.group { q.if_break { CallChainFormatter.new(self).format(q) }.if_flat { format_contents(q) } }
      else
        format_contents(q)
      end
    end

    def format_contents(q)
      q.format(call)
      q.format(block)
    end
  end

  # MLHS represents a list of values being destructured on the left-hand side
  # of a multiple assignment.
  #
  #     first, second, third = value
  #
  class MLHS < Node
    # Array[ARefField | ArgStar | Field | Ident | MLHSParen | VarField] the
    # parts of the left-hand side of a multiple assignment
    attr_reader :parts

    # [boolean] whether or not there is a trailing comma at the end of this
    # list, which impacts destructuring. It's an attr_accessor so that while
    # the syntax tree is being built it can be set by its parent node
    attr_accessor :comma

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, comma: false, location:, comments: [])
      @parts = parts
      @comma = comma
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_mlhs(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location, comma: comma, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
      q.text(",") if comma
    end
  end

  # MLHSParen represents parentheses being used to destruct values in a multiple
  # assignment on the left hand side.
  #
  #     (left, right) = value
  #
  class MLHSParen < Node
    # [MLHS | MLHSParen] the contents inside of the parentheses
    attr_reader :contents

    # [boolean] whether or not there is a trailing comma at the end of this
    # list, which impacts destructuring. It's an attr_accessor so that while
    # the syntax tree is being built it can be set by its parent node
    attr_accessor :comma

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(contents:, comma: false, location:, comments: [])
      @contents = contents
      @comma = comma
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_mlhs_paren(self)
    end

    def child_nodes
      [contents]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { contents: contents, location: location, comments: comments }
    end

    def format(q)
      parent = q.parent

      if parent.is_a?(MAssign) || parent.is_a?(MLHSParen)
        q.format(contents)
        q.text(",") if comma
      else
        q.group(0, "(", ")") do
          q.indent do
            q.breakable("")
            q.format(contents)
          end

          q.text(",") if comma
          q.breakable("")
        end
      end
    end
  end

  # ModuleDeclaration represents defining a module using the +module+ keyword.
  #
  #     module Namespace
  #     end
  #
  class ModuleDeclaration < Node
    # [ConstPathRef | ConstRef | TopConstRef] the name of the module
    attr_reader :constant

    # [BodyStmt] the expressions to be executed in the context of the module
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, bodystmt:, location:, comments: [])
      @constant = constant
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_module(self)
    end

    def child_nodes
      [constant, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        constant: constant,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      declaration = -> do
        q.group do
          q.text("module ")
          q.format(constant)
        end
      end

      if bodystmt.empty?
        q.group do
          declaration.call
          q.breakable(force: true)
          q.text("end")
        end
      else
        q.group do
          declaration.call

          q.indent do
            q.breakable(force: true)
            q.format(bodystmt)
          end

          q.breakable(force: true)
          q.text("end")
        end
      end
    end
  end

  # MRHS represents the values that are being assigned on the right-hand side of
  # a multiple assignment.
  #
  #     values = first, second, third
  #
  class MRHS < Node
    # Array[untyped] the parts that are being assigned
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:, comments: [])
      @parts = parts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_mrhs(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
    end
  end

  # Next represents using the +next+ keyword.
  #
  #     next
  #
  # The +next+ keyword can also optionally be called with an argument:
  #
  #     next value
  #
  # +next+ can even be called with multiple arguments, but only if parentheses
  # are omitted, as in:
  #
  #     next first, second, third
  #
  # If a single value is being given, parentheses can be used, as in:
  #
  #     next(value)
  #
  class Next < Node
    # [Args] the arguments passed to the next keyword
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_next(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("next", self).format(q)
    end
  end

  # Op represents an operator literal in the source.
  #
  #     1 + 2
  #
  # In the example above, the Op node represents the + operator.
  class Op < Node
    # [String] the operator
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_op(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # OpAssign represents assigning a value to a variable or constant using an
  # operator like += or ||=.
  #
  #     variable += value
  #
  class OpAssign < Node
    # [ARefField | ConstPathField | Field | TopConstField | VarField] the target
    # to assign the result of the expression to
    attr_reader :target

    # [Op] the operator being used for the assignment
    attr_reader :operator

    # [untyped] the expression to be assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, operator:, value:, location:, comments: [])
      @target = target
      @operator = operator
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_opassign(self)
    end

    def child_nodes
      [target, operator, value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        target: target,
        operator: operator,
        value: value,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(target)
        q.text(" ")
        q.format(operator)

        if skip_indent?
          q.text(" ")
          q.format(value)
        else
          q.indent do
            q.breakable
            q.format(value)
          end
        end
      end
    end

    private

    def skip_indent?
      target.comments.empty? &&
        (target.is_a?(ARefField) || AssignFormatting.skip_indent?(value))
    end
  end

  # If you have a modifier statement (for instance a modifier if statement or a
  # modifier while loop) there are times when you need to wrap the entire
  # statement in parentheses. This occurs when you have something like:
  #
  #     foo[:foo] =
  #       if bar?
  #         baz
  #       end
  #
  # Normally we would shorten this to an inline version, which would result in:
  #
  #     foo[:foo] = baz if bar?
  #
  # but this actually has different semantic meaning. The first example will
  # result in a nil being inserted into the hash for the :foo key, whereas the
  # second example will result in an empty hash because the if statement applies
  # to the entire assignment.
  #
  # We can fix this in a couple of ways. We can use the then keyword, as in:
  #
  #     foo[:foo] = if bar? then baz end
  #
  # But this isn't used very often. We can also just leave it as is with the
  # multi-line version, but for a short predicate and short value it looks
  # verbose. The last option and the one used here is to add parentheses on
  # both sides of the expression, as in:
  #
  #     foo[:foo] = (baz if bar?)
  #
  # This approach maintains the nice conciseness of the inline version, while
  # keeping the correct semantic meaning.
  module Parentheses
    NODES = [Args, Assign, Assoc, Binary, Call, Defined, MAssign, OpAssign]

    def self.flat(q)
      return yield unless NODES.include?(q.parent.class)

      q.text("(")
      yield
      q.text(")")
    end

    def self.break(q)
      return yield unless NODES.include?(q.parent.class)

      q.text("(")
      q.indent do
        q.breakable("")
        yield
      end
      q.breakable("")
      q.text(")")
    end
  end

  # def on_operator_ambiguous(value)
  #   value
  # end

  # Params represents defining parameters on a method or lambda.
  #
  #     def method(param) end
  #
  class Params < Node
    class OptionalFormatter
      # [Ident] the name of the parameter
      attr_reader :name

      # [untyped] the value of the parameter
      attr_reader :value

      def initialize(name, value)
        @name = name
        @value = value
      end

      def comments
        []
      end

      def format(q)
        q.format(name)
        q.text(" = ")
        q.format(value)
      end
    end

    class KeywordFormatter
      # [Ident] the name of the parameter
      attr_reader :name

      # [nil | untyped] the value of the parameter
      attr_reader :value

      def initialize(name, value)
        @name = name
        @value = value
      end

      def comments
        []
      end

      def format(q)
        q.format(name)

        if value
          q.text(" ")
          q.format(value)
        end
      end
    end

    class KeywordRestFormatter
      # [:nil | ArgsForward | KwRestParam] the value of the parameter
      attr_reader :value

      def initialize(value)
        @value = value
      end

      def comments
        []
      end

      def format(q)
        if value == :nil
          q.text("**nil")
        else
          q.format(value)
        end
      end
    end

    # [Array[ Ident ]] any required parameters
    attr_reader :requireds

    # [Array[ [ Ident, untyped ] ]] any optional parameters and their default
    # values
    attr_reader :optionals

    # [nil | ArgsForward | ExcessedComma | RestParam] the optional rest
    # parameter
    attr_reader :rest

    # [Array[ Ident ]] any positional parameters that exist after a rest
    # parameter
    attr_reader :posts

    # [Array[ [ Ident, nil | untyped ] ]] any keyword parameters and their
    # optional default values
    attr_reader :keywords

    # [nil | :nil | KwRestParam] the optional keyword rest parameter
    attr_reader :keyword_rest

    # [nil | BlockArg] the optional block parameter
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      requireds: [],
      optionals: [],
      rest: nil,
      posts: [],
      keywords: [],
      keyword_rest: nil,
      block: nil,
      location:,
      comments: []
    )
      @requireds = requireds
      @optionals = optionals
      @rest = rest
      @posts = posts
      @keywords = keywords
      @keyword_rest = keyword_rest
      @block = block
      @location = location
      @comments = comments
    end

    # Params nodes are the most complicated in the tree. Occasionally you want
    # to know if they are "empty", which means not having any parameters
    # declared. This logic accesses every kind of parameter and determines if
    # it's missing.
    def empty?
      requireds.empty? && optionals.empty? && !rest && posts.empty? &&
        keywords.empty? && !keyword_rest && !block
    end

    def accept(visitor)
      visitor.visit_params(self)
    end

    def child_nodes
      [
        *requireds,
        *optionals.flatten(1),
        rest,
        *posts,
        *keywords.flatten(1),
        (keyword_rest if keyword_rest != :nil),
        block
      ]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        location: location,
        requireds: requireds,
        optionals: optionals,
        rest: rest,
        posts: posts,
        keywords: keywords,
        keyword_rest: keyword_rest,
        block: block,
        comments: comments
      }
    end

    def format(q)
      parts = [
        *requireds,
        *optionals.map { |(name, value)| OptionalFormatter.new(name, value) }
      ]

      parts << rest if rest && !rest.is_a?(ExcessedComma)
      parts +=
        [
          *posts,
          *keywords.map { |(name, value)| KeywordFormatter.new(name, value) }
        ]

      parts << KeywordRestFormatter.new(keyword_rest) if keyword_rest
      parts << block if block

      contents = -> do
        q.seplist(parts) { |part| q.format(part) }
        q.format(rest) if rest && rest.is_a?(ExcessedComma)
      end

      if ![Def, Defs, DefEndless].include?(q.parent.class) || parts.empty?
        q.nest(0, &contents)
      else
        q.group(0, "(", ")") do
          q.indent do
            q.breakable("")
            contents.call
          end
          q.breakable("")
        end
      end
    end
  end

  # Paren represents using balanced parentheses in a couple places in a Ruby
  # program. In general parentheses can be used anywhere a Ruby expression can
  # be used.
  #
  #     (1 + 2)
  #
  class Paren < Node
    # [LParen] the left parenthesis that opened this statement
    attr_reader :lparen

    # [nil | untyped] the expression inside the parentheses
    attr_reader :contents

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lparen:, contents:, location:, comments: [])
      @lparen = lparen
      @contents = contents
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_paren(self)
    end

    def child_nodes
      [lparen, contents]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        lparen: lparen,
        contents: contents,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(lparen)

        if contents && (!contents.is_a?(Params) || !contents.empty?)
          q.indent do
            q.breakable("")
            q.format(contents)
          end
        end

        q.breakable("")
        q.text(")")
      end
    end
  end

  # Period represents the use of the +.+ operator. It is usually found in method
  # calls.
  class Period < Node
    # [String] the period
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_period(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # Program represents the overall syntax tree.
  class Program < Node
    # [Statements] the top-level expressions of the program
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statements:, location:, comments: [])
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_program(self)
    end

    def child_nodes
      [statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { statements: statements, location: location, comments: comments }
    end

    def format(q)
      q.format(statements)

      # We're going to put a newline on the end so that it always has one unless
      # it ends with the special __END__ syntax. In that case we want to
      # replicate the text exactly so we will just let it be.
      q.breakable(force: true) unless statements.body.last.is_a?(EndContent)
    end
  end

  # QSymbols represents a symbol literal array without interpolation.
  #
  #     %i[one two three]
  #
  class QSymbols < Node
    # [QSymbolsBeg] the token that opens this array literal
    attr_reader :beginning

    # [Array[ TStringContent ]] the elements of the array
    attr_reader :elements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, elements:, location:, comments: [])
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_qsymbols(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        elements: elements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      opening, closing = "%i[", "]"

      if elements.any? { |element| element.match?(/[\[\]]/) }
        opening = beginning.value
        closing = Quotes.matching(opening[2])
      end

      q.group(0, opening, closing) do
        q.indent do
          q.breakable("")
          q.seplist(elements, -> { q.breakable }) do |element|
            q.format(element)
          end
        end
        q.breakable("")
      end
    end
  end

  # QSymbolsBeg represents the beginning of a symbol literal array.
  #
  #     %i[one two three]
  #
  # In the snippet above, QSymbolsBeg represents the "%i[" token. Note that
  # these kinds of arrays can start with a lot of different delimiter types
  # (e.g., %i| or %i<).
  class QSymbolsBeg < Node
    # [String] the beginning of the array literal
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_qsymbols_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end

    def pretty_print(q)
      q.group(2, "(", ")") do
        q.text("qsymbols_beg")

        q.breakable
        q.pp(value)
      end
    end
  end

  # QWords represents a string literal array without interpolation.
  #
  #     %w[one two three]
  #
  class QWords < Node
    # [QWordsBeg] the token that opens this array literal
    attr_reader :beginning

    # [Array[ TStringContent ]] the elements of the array
    attr_reader :elements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, elements:, location:, comments: [])
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_qwords(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        elements: elements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      opening, closing = "%w[", "]"

      if elements.any? { |element| element.match?(/[\[\]]/) }
        opening = beginning.value
        closing = Quotes.matching(opening[2])
      end

      q.group(0, opening, closing) do
        q.indent do
          q.breakable("")
          q.seplist(elements, -> { q.breakable }) do |element|
            q.format(element)
          end
        end
        q.breakable("")
      end
    end
  end

  # QWordsBeg represents the beginning of a string literal array.
  #
  #     %w[one two three]
  #
  # In the snippet above, QWordsBeg represents the "%w[" token. Note that these
  # kinds of arrays can start with a lot of different delimiter types (e.g.,
  # %w| or %w<).
  class QWordsBeg < Node
    # [String] the beginning of the array literal
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_qwords_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # RationalLiteral represents the use of a rational number literal.
  #
  #     1r
  #
  class RationalLiteral < Node
    # [String] the rational number literal
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_rational(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # RBrace represents the use of a right brace, i.e., +++.
  class RBrace < Node
    # [String] the right brace
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_rbrace(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # RBracket represents the use of a right bracket, i.e., +]+.
  class RBracket < Node
    # [String] the right bracket
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_rbracket(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # Redo represents the use of the +redo+ keyword.
  #
  #     redo
  #
  class Redo < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_redo(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # RegexpContent represents the body of a regular expression.
  #
  #     /.+ #{pattern} .+/
  #
  # In the example above, a RegexpContent node represents everything contained
  # within the forward slashes.
  class RegexpContent < Node
    # [String] the opening of the regular expression
    attr_reader :beginning

    # [Array[ StringDVar | StringEmbExpr | TStringContent ]] the parts of the
    # regular expression
    attr_reader :parts

    def initialize(beginning:, parts:, location:)
      @beginning = beginning
      @parts = parts
      @location = location
    end

    def accept(visitor)
      visitor.visit_regexp_content(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { beginning: beginning, parts: parts, location: location }
    end
  end

  # RegexpBeg represents the start of a regular expression literal.
  #
  #     /.+/
  #
  # In the example above, RegexpBeg represents the first / token. Regular
  # expression literals can also be declared using the %r syntax, as in:
  #
  #     %r{.+}
  #
  class RegexpBeg < Node
    # [String] the beginning of the regular expression
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_regexp_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # RegexpEnd represents the end of a regular expression literal.
  #
  #     /.+/m
  #
  # In the example above, the RegexpEnd event represents the /m at the end of
  # the regular expression literal. You can also declare regular expression
  # literals using %r, as in:
  #
  #     %r{.+}m
  #
  class RegexpEnd < Node
    # [String] the end of the regular expression
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_regexp_end(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # RegexpLiteral represents a regular expression literal.
  #
  #     /.+/
  #
  class RegexpLiteral < Node
    # [String] the beginning of the regular expression literal
    attr_reader :beginning

    # [String] the ending of the regular expression literal
    attr_reader :ending

    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # regular expression literal
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, ending:, parts:, location:, comments: [])
      @beginning = beginning
      @ending = ending
      @parts = parts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_regexp_literal(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        ending: ending,
        parts: parts,
        location: location,
        comments: comments
      }
    end

    def format(q)
      braces = ambiguous?(q) || include?(%r{\/})

      if braces && include?(/[{}]/)
        q.group do
          q.text(beginning)
          q.format_each(parts)
          q.text(ending)
        end
      elsif braces
        q.group do
          q.text("%r{")

          if beginning == "/"
            # If we're changing from a forward slash to a %r{, then we can
            # replace any escaped forward slashes with regular forward slashes.
            parts.each do |part|
              if part.is_a?(TStringContent)
                q.text(part.value.gsub("\\/", "/"))
              else
                q.format(part)
              end
            end
          else
            q.format_each(parts)
          end

          q.text("}")
          q.text(ending[1..-1])
        end
      else
        q.group do
          q.text("/")
          q.format_each(parts)
          q.text("/")
          q.text(ending[1..-1])
        end
      end
    end

    private

    def include?(pattern)
      parts.any? do |part|
        part.is_a?(TStringContent) && part.value.match?(pattern)
      end
    end

    # If the first part of this regex is plain string content, we have a space
    # or an =, and we're contained within a command or command_call node, then
    # we want to use braces because otherwise we could end up with an ambiguous
    # operator, e.g. foo / bar/ or foo /=bar/
    def ambiguous?(q)
      return false if parts.empty?
      part = parts.first

      part.is_a?(TStringContent) && part.value.start_with?(" ", "=") &&
        q.parents.any? { |node| node.is_a?(Command) || node.is_a?(CommandCall) }
    end
  end

  # RescueEx represents the list of exceptions being rescued in a rescue clause.
  #
  #     begin
  #     rescue Exception => exception
  #     end
  #
  class RescueEx < Node
    # [untyped] the list of exceptions being rescued
    attr_reader :exceptions

    # [nil | Field | VarField] the expression being used to capture the raised
    # exception
    attr_reader :variable

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(exceptions:, variable:, location:, comments: [])
      @exceptions = exceptions
      @variable = variable
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_rescue_ex(self)
    end

    def child_nodes
      [*exceptions, variable]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        exceptions: exceptions,
        variable: variable,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        if exceptions
          q.text(" ")
          q.format(exceptions)
        end

        if variable
          q.text(" => ")
          q.format(variable)
        end
      end
    end
  end

  # Rescue represents the use of the rescue keyword inside of a BodyStmt node.
  #
  #     begin
  #     rescue
  #     end
  #
  class Rescue < Node
    # [Kw] the rescue keyword
    attr_reader :keyword

    # [RescueEx] the exceptions being rescued
    attr_reader :exception

    # [Statements] the expressions to evaluate when an error is rescued
    attr_reader :statements

    # [nil | Rescue] the optional next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      keyword:,
      exception:,
      statements:,
      consequent:,
      location:,
      comments: []
    )
      @keyword = keyword
      @exception = exception
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def bind_end(end_char, end_column)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: location.start_char,
          start_column: location.start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )

      if consequent
        consequent.bind_end(end_char, end_column)
        statements.bind_end(consequent.location.start_char, consequent.location.start_column)
      else
        statements.bind_end(end_char, end_column)
      end
    end

    def accept(visitor)
      visitor.visit_rescue(self)
    end

    def child_nodes
      [keyword, exception, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        keyword: keyword,
        exception: exception,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(keyword)

        if exception
          q.nest(keyword.value.length + 1) { q.format(exception) }
        else
          q.text(" StandardError")
        end

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end

        if consequent
          q.breakable(force: true)
          q.format(consequent)
        end
      end
    end
  end

  # RescueMod represents the use of the modifier form of a +rescue+ clause.
  #
  #     expression rescue value
  #
  class RescueMod < Node
    # [untyped] the expression to execute
    attr_reader :statement

    # [untyped] the value to use if the executed expression raises an error
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, value:, location:, comments: [])
      @statement = statement
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_rescue_mod(self)
    end

    def child_nodes
      [statement, value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        value: value,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group(0, "begin", "end") do
        q.indent do
          q.breakable(force: true)
          q.format(statement)
        end
        q.breakable(force: true)
        q.text("rescue StandardError")
        q.indent do
          q.breakable(force: true)
          q.format(value)
        end
        q.breakable(force: true)
      end
    end
  end

  # RestParam represents defining a parameter in a method definition that
  # accepts all remaining positional parameters.
  #
  #     def method(*rest) end
  #
  class RestParam < Node
    # [nil | Ident] the name of the parameter
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(name:, location:, comments: [])
      @name = name
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_rest_param(self)
    end

    def child_nodes
      [name]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("*")
      q.format(name) if name
    end
  end

  # Retry represents the use of the +retry+ keyword.
  #
  #     retry
  #
  class Retry < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_retry(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # Return represents using the +return+ keyword with arguments.
  #
  #     return value
  #
  class Return < Node
    # [Args] the arguments being passed to the keyword
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_return(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("return", self).format(q)
    end
  end

  # Return0 represents the bare +return+ keyword with no arguments.
  #
  #     return
  #
  class Return0 < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_return0(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # RParen represents the use of a right parenthesis, i.e., +)+.
  class RParen < Node
    # [String] the parenthesis
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_rparen(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # SClass represents a block of statements that should be evaluated within the
  # context of the singleton class of an object. It's frequently used to define
  # singleton methods.
  #
  #     class << self
  #     end
  #
  class SClass < Node
    # [untyped] the target of the singleton class to enter
    attr_reader :target

    # [BodyStmt] the expressions to be executed
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, bodystmt:, location:, comments: [])
      @target = target
      @bodystmt = bodystmt
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_sclass(self)
    end

    def child_nodes
      [target, bodystmt]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        target: target,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group(0, "class << ", "end") do
        q.format(target)
        q.indent do
          q.breakable(force: true)
          q.format(bodystmt)
        end
        q.breakable(force: true)
      end
    end
  end

  # Everything that has a block of code inside of it has a list of statements.
  # Normally we would just track those as a node that has an array body, but we
  # have some special handling in order to handle empty statement lists. They
  # need to have the right location information, so all of the parent node of
  # stmts nodes will report back down the location information. We then
  # propagate that onto void_stmt nodes inside the stmts in order to make sure
  # all comments get printed appropriately.
  class Statements < Node
    # [SyntaxTree] the parser that is generating this node
    attr_reader :parser

    # [Array[ untyped ]] the list of expressions contained within this node
    attr_reader :body

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parser, body:, location:, comments: [])
      @parser = parser
      @body = body
      @location = location
      @comments = comments
    end

    def bind(start_char, start_column, end_char, end_column)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          start_column: start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )

      if body[0].is_a?(VoidStmt)
        location = body[0].location
        location =
          Location.new(
            start_line: location.start_line,
            start_char: start_char,
            start_column: start_column,
            end_line: location.end_line,
            end_char: start_char,
            end_column: end_column
          )

        body[0] = VoidStmt.new(location: location)
      end

      attach_comments(start_char, end_char)
    end

    def bind_end(end_char, end_column)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: location.start_char,
          start_column: location.start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )
    end

    def empty?
      body.all? do |statement|
        statement.is_a?(VoidStmt) && statement.comments.empty?
      end
    end

    def accept(visitor)
      visitor.visit_statements(self)
    end

    def child_nodes
      body
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parser: parser, body: body, location: location, comments: comments }
    end

    def format(q)
      line = nil

      # This handles a special case where you've got a block of statements where
      # the only value is a comment. In that case a lot of nodes like
      # brace_block will attempt to format as a single line, but since that
      # wouldn't work with a comment, we intentionally break the parent group.
      if body.length == 2
        void_stmt, comment = body

        if void_stmt.is_a?(VoidStmt) && comment.is_a?(Comment)
          q.format(comment)
          q.break_parent
          return
        end
      end

      access_controls =
        Hash.new do |hash, node|
          hash[node] = node.is_a?(VCall) &&
            %w[private protected public].include?(node.value.value)
        end

      body.each_with_index do |statement, index|
        next if statement.is_a?(VoidStmt)

        if line.nil?
          q.format(statement)
        elsif (statement.location.start_line - line) > 1
          q.breakable(force: true)
          q.breakable(force: true)
          q.format(statement)
        elsif access_controls[statement] || access_controls[body[index - 1]]
          q.breakable(force: true)
          q.breakable(force: true)
          q.format(statement)
        elsif statement.location.start_line != line
          q.breakable(force: true)
          q.format(statement)
        elsif !q.parent.is_a?(StringEmbExpr)
          q.breakable(force: true)
          q.format(statement)
        else
          q.text("; ")
          q.format(statement)
        end

        line = statement.location.end_line
      end
    end

    private

    # As efficiently as possible, gather up all of the comments that have been
    # found while this statements list was being parsed and add them into the
    # body.
    def attach_comments(start_char, end_char)
      parser_comments = parser.comments

      comment_index = 0
      body_index = 0

      while comment_index < parser_comments.size
        comment = parser_comments[comment_index]
        location = comment.location

        if !comment.inline? && (start_char <= location.start_char) && (end_char >= location.end_char) && !comment.ignore?
          while (node = body[body_index]) && (node.is_a?(VoidStmt) || node.location.start_char < location.start_char)
            body_index += 1
          end

          if body_index != 0 && body[body_index - 1].location.start_char < location.start_char && body[body_index - 1].location.end_char > location.start_char
            # The previous node entirely encapsules the comment, so we don't
            # want to attach it here since it will get attached normally. This
            # is mostly in the case of hash and array literals.
            comment_index += 1
          else
            parser_comments.delete_at(comment_index)
            body.insert(body_index, comment)
          end
        else
          comment_index += 1
        end
      end
    end
  end

  # StringContent represents the contents of a string-like value.
  #
  #     "string"
  #
  class StringContent < Node
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # string
    attr_reader :parts

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def accept(visitor)
      visitor.visit_string_content(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location }
    end
  end

  # StringConcat represents concatenating two strings together using a backward
  # slash.
  #
  #     "first" \
  #       "second"
  #
  class StringConcat < Node
    # [StringConcat | StringLiteral] the left side of the concatenation
    attr_reader :left

    # [StringLiteral] the right side of the concatenation
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:, comments: [])
      @left = left
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_string_concat(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { left: left, right: right, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.format(left)
        q.text(' \\')
        q.indent do
          q.breakable(force: true)
          q.format(right)
        end
      end
    end
  end

  # StringDVar represents shorthand interpolation of a variable into a string.
  # It allows you to take an instance variable, class variable, or global
  # variable and omit the braces when interpolating.
  #
  #     "#@variable"
  #
  class StringDVar < Node
    # [Backref | VarRef] the variable being interpolated
    attr_reader :variable

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(variable:, location:, comments: [])
      @variable = variable
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_string_dvar(self)
    end

    def child_nodes
      [variable]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { variable: variable, location: location, comments: comments }
    end

    def format(q)
      q.text('#{')
      q.format(variable)
      q.text("}")
    end
  end

  # StringEmbExpr represents interpolated content. It can be contained within a
  # couple of different parent nodes, including regular expressions, strings,
  # and dynamic symbols.
  #
  #     "string #{expression}"
  #
  class StringEmbExpr < Node
    # [Statements] the expressions to be interpolated
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statements:, location:, comments: [])
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_string_embexpr(self)
    end

    def child_nodes
      [statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { statements: statements, location: location, comments: comments }
    end

    def format(q)
      if location.start_line == location.end_line
        # If the contents of this embedded expression were originally on the
        # same line in the source, then we're going to leave them in place and
        # assume that's the way the developer wanted this expression
        # represented.
        doc = q.group(0, '#{', "}") { q.format(statements) }
        RemoveBreaks.call(doc)
      else
        q.group do
          q.text('#{')
          q.indent do
            q.breakable("")
            q.format(statements)
          end
          q.breakable("")
          q.text("}")
        end
      end
    end
  end

  # StringLiteral represents a string literal.
  #
  #     "string"
  #
  class StringLiteral < Node
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # string literal
    attr_reader :parts

    # [String] which quote was used by the string literal
    attr_reader :quote

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, quote:, location:, comments: [])
      @parts = parts
      @quote = quote
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_string_literal(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, quote: quote, location: location, comments: comments }
    end

    def format(q)
      if parts.empty?
        q.text("#{q.quote}#{q.quote}")
        return
      end

      opening_quote, closing_quote =
        if !Quotes.locked?(self)
          [q.quote, q.quote]
        elsif quote.start_with?("%")
          [quote, Quotes.matching(quote[/%[qQ]?(.)/, 1])]
        else
          [quote, quote]
        end

      q.group(0, opening_quote, closing_quote) do
        parts.each do |part|
          if part.is_a?(TStringContent)
            value = Quotes.normalize(part.value, closing_quote)
            separator = -> { q.breakable(force: true, indent: false) }
            q.seplist(value.split(/\r?\n/, -1), separator) do |text|
              q.text(text)
            end
          else
            q.format(part)
          end
        end
      end
    end
  end

  # Super represents using the +super+ keyword with arguments. It can optionally
  # use parentheses.
  #
  #     super(value)
  #
  class Super < Node
    # [ArgParen | Args] the arguments to the keyword
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_super(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("super")

        if arguments.is_a?(ArgParen)
          q.format(arguments)
        else
          q.text(" ")
          q.nest("super ".length) { q.format(arguments) }
        end
      end
    end
  end

  # SymBeg represents the beginning of a symbol literal.
  #
  #     :symbol
  #
  # SymBeg is also used for dynamic symbols, as in:
  #
  #     :"symbol"
  #
  # Finally, SymBeg is also used for symbols using the %s syntax, as in:
  #
  #     %s[symbol]
  #
  # The value of this node is a string. In most cases (as in the first example
  # above) it will contain just ":". In the case of dynamic symbols it will
  # contain ":'" or ":\"". In the case of %s symbols, it will contain the start
  # of the symbol including the %s and the delimiter.
  class SymBeg < Node
    # [String] the beginning of the symbol
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_symbeg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # SymbolContent represents symbol contents and is always the child of a
  # SymbolLiteral node.
  #
  #     :symbol
  #
  class SymbolContent < Node
    # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op] the value of the
    # symbol
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_symbol_content(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # SymbolLiteral represents a symbol in the system with no interpolation
  # (as opposed to a DynaSymbol which has interpolation).
  #
  #     :symbol
  #
  class SymbolLiteral < Node
    # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op] the value of the
    # symbol
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_symbol_literal(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(":")
      q.format(value)
    end
  end

  # Symbols represents a symbol array literal with interpolation.
  #
  #     %I[one two three]
  #
  class Symbols < Node
    # [SymbolsBeg] the token that opens this array literal
    attr_reader :beginning

    # [Array[ Word ]] the words in the symbol array literal
    attr_reader :elements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, elements:, location:, comments: [])
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_symbols(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        elements: elements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      opening, closing = "%I[", "]"

      if elements.any? { |element| element.match?(/[\[\]]/) }
        opening = beginning.value
        closing = Quotes.matching(opening[2])
      end

      q.group(0, opening, closing) do
        q.indent do
          q.breakable("")
          q.seplist(elements, -> { q.breakable }) do |element|
            q.format(element)
          end
        end
        q.breakable("")
      end
    end
  end

  # SymbolsBeg represents the start of a symbol array literal with
  # interpolation.
  #
  #     %I[one two three]
  #
  # In the snippet above, SymbolsBeg represents the "%I[" token. Note that these
  # kinds of arrays can start with a lot of different delimiter types
  # (e.g., %I| or %I<).
  class SymbolsBeg < Node
    # [String] the beginning of the symbol literal array
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_symbols_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # TLambda represents the beginning of a lambda literal.
  #
  #     -> { value }
  #
  # In the example above the TLambda represents the +->+ operator.
  class TLambda < Node
    # [String] the beginning of the lambda literal
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_tlambda(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # TLamBeg represents the beginning of the body of a lambda literal using
  # braces.
  #
  #     -> { value }
  #
  # In the example above the TLamBeg represents the +{+ operator.
  class TLamBeg < Node
    # [String] the beginning of the body of the lambda literal
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_tlambeg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # TopConstField is always the child node of some kind of assignment. It
  # represents when you're assigning to a constant that is being referenced at
  # the top level.
  #
  #     ::Constant = value
  #
  class TopConstField < Node
    # [Const] the constant being assigned
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, location:, comments: [])
      @constant = constant
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_top_const_field(self)
    end

    def child_nodes
      [constant]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.text("::")
      q.format(constant)
    end
  end

  # TopConstRef is very similar to TopConstField except that it is not involved
  # in an assignment.
  #
  #     ::Constant
  #
  class TopConstRef < Node
    # [Const] the constant being referenced
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, location:, comments: [])
      @constant = constant
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_top_const_ref(self)
    end

    def child_nodes
      [constant]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.text("::")
      q.format(constant)
    end
  end

  # TStringBeg represents the beginning of a string literal.
  #
  #     "string"
  #
  # In the example above, TStringBeg represents the first set of quotes. Strings
  # can also use single quotes. They can also be declared using the +%q+ and
  # +%Q+ syntax, as in:
  #
  #     %q{string}
  #
  class TStringBeg < Node
    # [String] the beginning of the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_tstring_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # TStringContent represents plain characters inside of an entity that accepts
  # string content like a string, heredoc, command string, or regular
  # expression.
  #
  #     "string"
  #
  # In the example above, TStringContent represents the +string+ token contained
  # within the string.
  class TStringContent < Node
    # [String] the content of the string
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def match?(pattern)
      value.match?(pattern)
    end

    def accept(visitor)
      visitor.visit_tstring_content(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # TStringEnd represents the end of a string literal.
  #
  #     "string"
  #
  # In the example above, TStringEnd represents the second set of quotes.
  # Strings can also use single quotes. They can also be declared using the +%q+
  # and +%Q+ syntax, as in:
  #
  #     %q{string}
  #
  class TStringEnd < Node
    # [String] the end of the string
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_tstring_end(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # Not represents the unary +not+ method being called on an expression.
  #
  #     not value
  #
  class Not < Node
    # [nil | untyped] the statement on which to operate
    attr_reader :statement

    # [boolean] whether or not parentheses were used
    attr_reader :parentheses

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, parentheses:, location:, comments: [])
      @statement = statement
      @parentheses = parentheses
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_not(self)
    end

    def child_nodes
      [statement]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        parentheses: parentheses,
        location: location,
        comments: comments
      }
    end

    def format(q)
      parent = q.parents.take(2)[1]
      ternary = (parent.is_a?(If) || parent.is_a?(Unless)) && Ternaryable.call(q, parent)

      q.text("not")

      if parentheses
        q.text("(")
      elsif ternary
        q.if_break { q.text(" ") }.if_flat { q.text("(") }
      else
        q.text(" ")
      end

      q.format(statement) if statement

      if parentheses
        q.text(")")
      elsif ternary
        q.if_flat { q.text(")") }
      end
    end
  end

  # Unary represents a unary method being called on an expression, as in +!+ or
  # +~+.
  #
  #     !value
  #
  class Unary < Node
    # [String] the operator being used
    attr_reader :operator

    # [untyped] the statement on which to operate
    attr_reader :statement

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(operator:, statement:, location:, comments: [])
      @operator = operator
      @statement = statement
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_unary(self)
    end

    def child_nodes
      [statement]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        operator: operator,
        statement: statement,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.text(operator)
      q.format(statement)
    end
  end

  # Undef represents the use of the +undef+ keyword.
  #
  #     undef method
  #
  class Undef < Node
    class UndefArgumentFormatter
      # [DynaSymbol | SymbolLiteral] the symbol to undefine
      attr_reader :node

      def initialize(node)
        @node = node
      end

      def comments
        if node.is_a?(SymbolLiteral)
          node.comments + node.value.comments
        else
          node.comments
        end
      end

      def format(q)
        node.is_a?(SymbolLiteral) ? q.format(node.value) : q.format(node)
      end
    end

    # [Array[ DynaSymbol | SymbolLiteral ]] the symbols to undefine
    attr_reader :symbols

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(symbols:, location:, comments: [])
      @symbols = symbols
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_undef(self)
    end

    def child_nodes
      symbols
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { symbols: symbols, location: location, comments: comments }
    end

    def format(q)
      keyword = "undef "
      formatters = symbols.map { |symbol| UndefArgumentFormatter.new(symbol) }

      q.group do
        q.text(keyword)
        q.nest(keyword.length) do
          q.seplist(formatters) { |formatter| q.format(formatter) }
        end
      end
    end
  end

  # Unless represents the first clause in an +unless+ chain.
  #
  #     unless predicate
  #     end
  #
  class Unless < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil, Elsif, Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      predicate:,
      statements:,
      consequent:,
      location:,
      comments: []
    )
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_unless(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      ConditionalFormatter.new("unless", self).format(q)
    end
  end

  # UnlessMod represents the modifier form of an +unless+ statement.
  #
  #     expression unless predicate
  #
  class UnlessMod < Node
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, predicate:, location:, comments: [])
      @statement = statement
      @predicate = predicate
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_unless_mod(self)
    end

    def child_nodes
      [statement, predicate]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        predicate: predicate,
        location: location,
        comments: comments
      }
    end

    def format(q)
      ConditionalModFormatter.new("unless", self).format(q)
    end
  end

  # Formats an Until, UntilMod, While, or WhileMod node.
  class LoopFormatter
    # [String] the name of the keyword used for this loop
    attr_reader :keyword

    # [Until | UntilMod | While | WhileMod] the node that is being formatted
    attr_reader :node

    # [untyped] the statements associated with the node
    attr_reader :statements

    def initialize(keyword, node, statements)
      @keyword = keyword
      @node = node
      @statements = statements
    end

    def format(q)
      if ContainsAssignment.call(node.predicate)
        format_break(q)
        q.break_parent
        return
      end

      q.group do
        q.if_break { format_break(q) }.if_flat do
          Parentheses.flat(q) do
            q.format(statements)
            q.text(" #{keyword} ")
            q.format(node.predicate)
          end
        end
      end
    end

    private

    def format_break(q)
      q.text("#{keyword} ")
      q.nest(keyword.length + 1) { q.format(node.predicate) }
      q.indent do
        q.breakable("")
        q.format(statements)
      end
      q.breakable("")
      q.text("end")
    end
  end

  # Until represents an +until+ loop.
  #
  #     until predicate
  #     end
  #
  class Until < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, location:, comments: [])
      @predicate = predicate
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_until(self)
    end

    def child_nodes
      [predicate, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      if statements.empty?
        keyword = "until "

        q.group do
          q.text(keyword)
          q.nest(keyword.length) { q.format(predicate) }
          q.breakable(force: true)
          q.text("end")
        end
      else
        LoopFormatter.new("until", self, statements).format(q)
      end
    end
  end

  # UntilMod represents the modifier form of a +until+ loop.
  #
  #     expression until predicate
  #
  class UntilMod < Node
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, predicate:, location:, comments: [])
      @statement = statement
      @predicate = predicate
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_until_mod(self)
    end

    def child_nodes
      [statement, predicate]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        predicate: predicate,
        location: location,
        comments: comments
      }
    end

    def format(q)
      # If we're in the modifier form and we're modifying a `begin`, then this
      # is a special case where we need to explicitly use the modifier form
      # because otherwise the semantic meaning changes. This looks like:
      #
      #     begin
      #       foo
      #     end until bar
      #
      # Also, if the statement of the modifier includes an assignment, then we
      # can't know for certain that it won't impact the predicate, so we need to
      # force it to stay as it is. This looks like:
      #
      #     foo = bar until foo
      #
      if statement.is_a?(Begin) || ContainsAssignment.call(statement)
        q.format(statement)
        q.text(" until ")
        q.format(predicate)
      else
        LoopFormatter.new("until", self, statement).format(q)
      end
    end
  end

  # VarAlias represents when you're using the +alias+ keyword with global
  # variable arguments.
  #
  #     alias $new $old
  #
  class VarAlias < Node
    # [GVar] the new alias of the variable
    attr_reader :left

    # [Backref | GVar] the current name of the variable to be aliased
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:, comments: [])
      @left = left
      @right = right
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_var_alias(self)
    end

    def child_nodes
      [left, right]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { left: left, right: right, location: location, comments: comments }
    end

    def format(q)
      keyword = "alias "

      q.text(keyword)
      q.format(left)
      q.text(" ")
      q.format(right)
    end
  end

  # VarField represents a variable that is being assigned a value. As such, it
  # is always a child of an assignment type node.
  #
  #     variable = value
  #
  # In the example above, the VarField node represents the +variable+ token.
  class VarField < Node
    # [nil | Const | CVar | GVar | Ident | IVar] the target of this node
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_var_field(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      if value == :nil
        q.text("nil")
      elsif value
        q.format(value)
      end
    end
  end

  # VarRef represents a variable reference.
  #
  #     true
  #
  # This can be a plain local variable like the example above. It can also be a
  # constant, a class variable, a global variable, an instance variable, a
  # keyword (like +self+, +nil+, +true+, or +false+), or a numbered block
  # variable.
  class VarRef < Node
    # [Const | CVar | GVar | Ident | IVar | Kw] the value of this node
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_var_ref(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.format(value)
    end
  end

  # PinnedVarRef represents a pinned variable reference within a pattern
  # matching pattern.
  #
  #     case value
  #     in ^variable
  #     end
  #
  # This can be a plain local variable like the example above. It can also be a
  # a class variable, a global variable, or an instance variable.
  class PinnedVarRef < Node
    # [VarRef] the value of this node
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_pinned_var_ref(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("^")
        q.format(value)
      end
    end
  end

  # VCall represent any plain named object with Ruby that could be either a
  # local variable or a method call.
  #
  #     variable
  #
  class VCall < Node
    # [Ident] the value of this expression
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_vcall(self)
    end

    def child_nodes
      [value]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.format(value)
    end
  end

  # VoidStmt represents an empty lexical block of code.
  #
  #     ;;
  #
  class VoidStmt < Node
    # [Location] the location of this node
    attr_reader :location

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:, comments: [])
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_void_stmt(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { location: location, comments: comments }
    end

    def format(q)
    end
  end

  # When represents a +when+ clause in a +case+ chain.
  #
  #     case value
  #     when predicate
  #     end
  #
  class When < Node
    # [Args] the arguments to the when clause
    attr_reader :arguments

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Else | When] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      arguments:,
      statements:,
      consequent:,
      location:,
      comments: []
    )
      @arguments = arguments
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_when(self)
    end

    def child_nodes
      [arguments, statements, consequent]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        arguments: arguments,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    def format(q)
      keyword = "when "

      q.group do
        q.group do
          q.text(keyword)
          q.nest(keyword.length) do
            if arguments.comments.any?
              q.format(arguments)
            else
              separator = -> { q.group { q.comma_breakable } }
              q.seplist(arguments.parts, separator) { |part| q.format(part) }
            end

            # Very special case here. If you're inside of a when clause and the
            # last argument to the predicate is and endless range, then you are
            # forced to use the "then" keyword to make it parse properly.
            last = arguments.parts.last
            if (last.is_a?(Dot2) || last.is_a?(Dot3)) && !last.right
              q.text(" then")
            end
          end
        end

        unless statements.empty?
          q.indent do
            q.breakable(force: true)
            q.format(statements)
          end
        end

        if consequent
          q.breakable(force: true)
          q.format(consequent)
        end
      end
    end
  end

  # While represents a +while+ loop.
  #
  #     while predicate
  #     end
  #
  class While < Node
    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, location:, comments: [])
      @predicate = predicate
      @statements = statements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_while(self)
    end

    def child_nodes
      [predicate, statements]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        predicate: predicate,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      if statements.empty?
        keyword = "while "

        q.group do
          q.text(keyword)
          q.nest(keyword.length) { q.format(predicate) }
          q.breakable(force: true)
          q.text("end")
        end
      else
        LoopFormatter.new("while", self, statements).format(q)
      end
    end
  end

  # WhileMod represents the modifier form of a +while+ loop.
  #
  #     expression while predicate
  #
  class WhileMod < Node
    # [untyped] the expression to be executed
    attr_reader :statement

    # [untyped] the expression to be checked
    attr_reader :predicate

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, predicate:, location:, comments: [])
      @statement = statement
      @predicate = predicate
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_while_mod(self)
    end

    def child_nodes
      [statement, predicate]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        statement: statement,
        predicate: predicate,
        location: location,
        comments: comments
      }
    end

    def format(q)
      # If we're in the modifier form and we're modifying a `begin`, then this
      # is a special case where we need to explicitly use the modifier form
      # because otherwise the semantic meaning changes. This looks like:
      #
      #     begin
      #       foo
      #     end while bar
      #
      # Also, if the statement of the modifier includes an assignment, then we
      # can't know for certain that it won't impact the predicate, so we need to
      # force it to stay as it is. This looks like:
      #
      #     foo = bar while foo
      #
      if statement.is_a?(Begin) || ContainsAssignment.call(statement)
        q.format(statement)
        q.text(" while ")
        q.format(predicate)
      else
        LoopFormatter.new("while", self, statement).format(q)
      end
    end
  end

  # Word represents an element within a special array literal that accepts
  # interpolation.
  #
  #     %W[a#{b}c xyz]
  #
  # In the example above, there would be two Word nodes within a parent Words
  # node.
  class Word < Node
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # word
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:, comments: [])
      @parts = parts
      @location = location
      @comments = comments
    end

    def match?(pattern)
      parts.any? { |part| part.is_a?(TStringContent) && part.match?(pattern) }
    end

    def accept(visitor)
      visitor.visit_word(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.format_each(parts)
    end
  end

  # Words represents a string literal array with interpolation.
  #
  #     %W[one two three]
  #
  class Words < Node
    # [WordsBeg] the token that opens this array literal
    attr_reader :beginning

    # [Array[ Word ]] the elements of this array
    attr_reader :elements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, elements:, location:, comments: [])
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_words(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      {
        beginning: beginning,
        elements: elements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      opening, closing = "%W[", "]"

      if elements.any? { |element| element.match?(/[\[\]]/) }
        opening = beginning.value
        closing = Quotes.matching(opening[2])
      end

      q.group(0, opening, closing) do
        q.indent do
          q.breakable("")
          q.seplist(elements, -> { q.breakable }) do |element|
            q.format(element)
          end
        end
        q.breakable("")
      end
    end
  end

  # WordsBeg represents the beginning of a string literal array with
  # interpolation.
  #
  #     %W[one two three]
  #
  # In the snippet above, a WordsBeg would be created with the value of "%W[".
  # Note that these kinds of arrays can start with a lot of different delimiter
  # types (e.g., %W| or %W<).
  class WordsBeg < Node
    # [String] the start of the word literal array
    attr_reader :value

    def initialize(value:, location:)
      @value = value
      @location = location
    end

    def accept(visitor)
      visitor.visit_words_beg(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location }
    end
  end

  # XString represents the contents of an XStringLiteral.
  #
  #     `ls`
  #
  class XString < Node
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # xstring
    attr_reader :parts

    def initialize(parts:, location:)
      @parts = parts
      @location = location
    end

    def accept(visitor)
      visitor.visit_xstring(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location }
    end
  end

  # XStringLiteral represents a string that gets executed.
  #
  #     `ls`
  #
  class XStringLiteral < Node
    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # xstring
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:, comments: [])
      @parts = parts
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_xstring_literal(self)
    end

    def child_nodes
      parts
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.text("`")
      q.format_each(parts)
      q.text("`")
    end
  end

  # Yield represents using the +yield+ keyword with arguments.
  #
  #     yield value
  #
  class Yield < Node
    # [Args | Paren] the arguments passed to the yield
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:, comments: [])
      @arguments = arguments
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_yield(self)
    end

    def child_nodes
      [arguments]
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("yield")

        if arguments.is_a?(Paren)
          q.format(arguments)
        else
          q.if_break { q.text("(") }.if_flat { q.text(" ") }
          q.indent do
            q.breakable("")
            q.format(arguments)
          end
          q.breakable("")
          q.if_break { q.text(")") }
        end
      end
    end
  end

  # Yield0 represents the bare +yield+ keyword with no arguments.
  #
  #     yield
  #
  class Yield0 < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_yield0(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end

  # ZSuper represents the bare +super+ keyword with no arguments.
  #
  #     super
  #
  class ZSuper < Node
    # [String] the value of the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:, comments: [])
      @value = value
      @location = location
      @comments = comments
    end

    def accept(visitor)
      visitor.visit_zsuper(self)
    end

    def child_nodes
      []
    end

    alias deconstruct child_nodes

    def deconstruct_keys(keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end
  end
end
