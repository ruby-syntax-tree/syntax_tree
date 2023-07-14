# frozen_string_literal: true

module SyntaxTree
  # Represents the location of a node in the tree from the source code.
  class Location
    attr_reader :start_line,
                :start_char,
                :start_column,
                :end_line,
                :end_char,
                :end_column

    def initialize(
      start_line:,
      start_char:,
      start_column:,
      end_line:,
      end_char:,
      end_column:
    )
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

    def deconstruct_keys(_keys)
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
      new(
        start_line: line,
        start_char: char,
        start_column: column,
        end_line: line,
        end_char: char,
        end_column: column
      )
    end

    # A convenience method that is typically used when you don't care about the
    # location of a node, but need to create a Location instance to pass to a
    # constructor.
    def self.default
      new(
        start_line: 1,
        start_char: 0,
        start_column: 0,
        end_line: 1,
        end_char: 0,
        end_column: 0
      )
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

    def start_char
      location.start_char
    end

    def end_char
      location.end_char
    end

    def pretty_print(q)
      accept(PrettyPrintVisitor.new(q))
    end

    def to_json(*opts)
      accept(JSONVisitor.new).to_json(*opts)
    end

    def to_mermaid
      accept(MermaidVisitor.new)
    end

    def construct_keys
      PrettierPrint.format(+"") { |q| accept(MatchVisitor.new(q)) }
    end
  end

  # When we're implementing the === operator for a node, we oftentimes need to
  # compare two arrays. We want to skip over the === definition of array and use
  # our own here, so we do that using this module.
  module ArrayMatch
    def self.call(left, right)
      left.length === right.length &&
        left
          .zip(right)
          .all? { |left_value, right_value| left_value === right_value }
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

    def initialize(lbrace:, statements:, location:)
      @lbrace = lbrace
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_BEGIN(self)
    end

    def child_nodes
      [lbrace, statements]
    end

    def copy(lbrace: nil, statements: nil, location: nil)
      node =
        BEGINBlock.new(
          lbrace: lbrace || self.lbrace,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
          q.breakable_space
          q.format(statements)
        end
        q.breakable_space
        q.text("}")
      end
    end

    def ===(other)
      other.is_a?(BEGINBlock) && lbrace === other.lbrace &&
        statements === other.statements
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_CHAR(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        CHAR.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(CHAR) && value === other.value
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

    def initialize(lbrace:, statements:, location:)
      @lbrace = lbrace
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_END(self)
    end

    def child_nodes
      [lbrace, statements]
    end

    def copy(lbrace: nil, statements: nil, location: nil)
      node =
        ENDBlock.new(
          lbrace: lbrace || self.lbrace,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
          q.breakable_space
          q.format(statements)
        end
        q.breakable_space
        q.text("}")
      end
    end

    def ===(other)
      other.is_a?(ENDBlock) && lbrace === other.lbrace &&
        statements === other.statements
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit___end__(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        EndContent.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("__END__")
      q.breakable_force

      first = true
      value.each_line(chomp: true) do |line|
        if first
          first = false
        else
          q.breakable_return
        end

        q.text(line)
      end

      q.breakable_return if value.end_with?("\n")
    end

    def ===(other)
      other.is_a?(EndContent) && value === other.value
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
  class AliasNode < Node
    # Formats an argument to the alias keyword. For symbol literals it uses the
    # value of the symbol directly to look like bare words.
    class AliasArgumentFormatter
      # [Backref | DynaSymbol | GVar | SymbolLiteral] the argument being passed
      # to alias
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

    # [DynaSymbol | GVar | SymbolLiteral] the new name of the method
    attr_reader :left

    # [Backref | DynaSymbol | GVar | SymbolLiteral] the old name of the method
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_alias(self)
    end

    def child_nodes
      [left, right]
    end

    def copy(left: nil, right: nil, location: nil)
      node =
        AliasNode.new(
          left: left || self.left,
          right: right || self.right,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            left_argument.comments.any? ? q.breakable_force : q.breakable_space
            q.format(AliasArgumentFormatter.new(right), stackable: false)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(AliasNode) && left === other.left && right === other.right
    end

    def var_alias?
      left.is_a?(GVar)
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
    # [Node] the value being indexed
    attr_reader :collection

    # [nil | Args] the value being passed within the brackets
    attr_reader :index

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(collection:, index:, location:)
      @collection = collection
      @index = index
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_aref(self)
    end

    def child_nodes
      [collection, index]
    end

    def copy(collection: nil, index: nil, location: nil)
      node =
        ARef.new(
          collection: collection || self.collection,
          index: index || self.index,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_empty
            q.format(index)
          end
          q.breakable_empty
        end

        q.text("]")
      end
    end

    def ===(other)
      other.is_a?(ARef) && collection === other.collection &&
        index === other.index
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
    # [Node] the value being indexed
    attr_reader :collection

    # [nil | Args] the value being passed within the brackets
    attr_reader :index

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(collection:, index:, location:)
      @collection = collection
      @index = index
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_aref_field(self)
    end

    def child_nodes
      [collection, index]
    end

    def copy(collection: nil, index: nil, location: nil)
      node =
        ARefField.new(
          collection: collection || self.collection,
          index: index || self.index,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_empty
            q.format(index)
          end
          q.breakable_empty
        end

        q.text("]")
      end
    end

    def ===(other)
      other.is_a?(ARefField) && collection === other.collection &&
        index === other.index
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

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_arg_paren(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        ArgParen.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      unless arguments
        q.text("()")
        return
      end

      q.text("(")
      q.group do
        q.indent do
          q.breakable_empty
          q.format(arguments)
          q.if_break { q.text(",") } if q.trailing_comma? && trailing_comma?
        end
        q.breakable_empty
      end
      q.text(")")
    end

    def ===(other)
      other.is_a?(ArgParen) && arguments === other.arguments
    end

    def arity
      arguments&.arity || 0
    end

    private

    def trailing_comma?
      arguments = self.arguments
      return false unless arguments.is_a?(Args)

      parts = arguments.parts
      if parts.last.is_a?(ArgBlock)
        # If the last argument is a block, then we can't put a trailing comma
        # after it without resulting in a syntax error.
        false
      elsif (parts.length == 1) && (part = parts.first) &&
            (part.is_a?(Command) || part.is_a?(CommandCall))
        # If the only argument is a command or command call, then a trailing
        # comma would be parsed as part of that expression instead of on this
        # one, so we don't want to add a trailing comma.
        false
      else
        # Otherwise, we should be okay to add a trailing comma.
        true
      end
    end
  end

  # Args represents a list of arguments being passed to a method call or array
  # literal.
  #
  #     method(first, second, third)
  #
  class Args < Node
    # [Array[ Node ]] the arguments that this node wraps
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:)
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_args(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, location: nil)
      node =
        Args.new(
          parts: parts || self.parts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
    end

    def ===(other)
      other.is_a?(Args) && ArrayMatch.call(parts, other.parts)
    end

    def arity
      parts.sum do |part|
        case part
        when ArgStar, ArgsForward
          Float::INFINITY
        when BareAssocHash
          part.assocs.sum do |assoc|
            assoc.is_a?(AssocSplat) ? Float::INFINITY : 1
          end
        else
          1
        end
      end
    end
  end

  # ArgBlock represents using a block operator on an expression.
  #
  #     method(&expression)
  #
  class ArgBlock < Node
    # [nil | Node] the expression being turned into a block
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_arg_block(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        ArgBlock.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("&")
      q.format(value) if value
    end

    def ===(other)
      other.is_a?(ArgBlock) && value === other.value
    end
  end

  # Star represents using a splat operator on an expression.
  #
  #     method(*arguments)
  #
  class ArgStar < Node
    # [nil | Node] the expression being splatted
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_arg_star(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        ArgStar.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("*")
      q.format(value) if value
    end

    def ===(other)
      other.is_a?(ArgStar) && value === other.value
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
    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:)
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_args_forward(self)
    end

    def child_nodes
      []
    end

    def copy(location: nil)
      node = ArgsForward.new(location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { location: location, comments: comments }
    end

    def format(q)
      q.text("...")
    end

    def ===(other)
      other.is_a?(ArgsForward)
    end

    def arity
      Float::INFINITY
    end
  end

  # ArrayLiteral represents an array literal, which can optionally contain
  # elements.
  #
  #     []
  #     [one, two, three]
  #
  class ArrayLiteral < Node
    # It's very common to use seplist with ->(q) { q.breakable_space }. We wrap
    # that pattern into an object to cut down on having to create a bunch of
    # lambdas all over the place.
    class BreakableSpaceSeparator
      def call(q)
        q.breakable_space
      end
    end

    BREAKABLE_SPACE_SEPARATOR = BreakableSpaceSeparator.new.freeze

    # Formats an array of multiple simple string literals into the %w syntax.
    class QWordsFormatter
      # [Args] the contents of the array
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def format(q)
        q.text("%w[")
        q.group do
          q.indent do
            q.breakable_empty
            q.seplist(contents.parts, BREAKABLE_SPACE_SEPARATOR) do |part|
              if part.is_a?(StringLiteral)
                q.format(part.parts.first)
              else
                q.text(part.value[1..])
              end
            end
          end
          q.breakable_empty
        end
        q.text("]")
      end
    end

    # Formats an array of multiple simple symbol literals into the %i syntax.
    class QSymbolsFormatter
      # [Args] the contents of the array
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def format(q)
        q.text("%i[")
        q.group do
          q.indent do
            q.breakable_empty
            q.seplist(contents.parts, BREAKABLE_SPACE_SEPARATOR) do |part|
              q.format(part.value)
            end
          end
          q.breakable_empty
        end
        q.text("]")
      end
    end

    # This is a special formatter used if the array literal contains no values
    # but _does_ contain comments. In this case we do some special formatting to
    # make sure the comments gets indented properly.
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
              q.breakable_force
              comment.format(q)
            end
          end
          q.breakable_force
          q.text("]")
        end
      end
    end

    # [nil | LBracket | QSymbolsBeg | QWordsBeg | SymbolsBeg | WordsBeg] the
    # bracket that opens this array
    attr_reader :lbracket

    # [nil | Args] the contents of the array
    attr_reader :contents

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbracket:, contents:, location:)
      @lbracket = lbracket
      @contents = contents
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_array(self)
    end

    def child_nodes
      [lbracket, contents]
    end

    def copy(lbracket: nil, contents: nil, location: nil)
      node =
        ArrayLiteral.new(
          lbracket: lbracket || self.lbracket,
          contents: contents || self.contents,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        lbracket: lbracket,
        contents: contents,
        location: location,
        comments: comments
      }
    end

    def format(q)
      lbracket = self.lbracket
      contents = self.contents

      if lbracket.is_a?(LBracket) && lbracket.comments.empty? && contents &&
           contents.comments.empty? && contents.parts.length > 1
        if qwords?
          QWordsFormatter.new(contents).format(q)
          return
        end

        if qsymbols?
          QSymbolsFormatter.new(contents).format(q)
          return
        end
      end

      if empty_with_comments?
        EmptyWithCommentsFormatter.new(lbracket).format(q)
        return
      end

      q.group do
        q.format(lbracket)

        if contents
          q.indent do
            q.breakable_empty
            q.format(contents)
            q.if_break { q.text(",") } if q.trailing_comma?
          end
        end

        q.breakable_empty
        q.text("]")
      end
    end

    def ===(other)
      other.is_a?(ArrayLiteral) && lbracket === other.lbracket &&
        contents === other.contents
    end

    private

    def qwords?
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
      contents.parts.all? do |part|
        part.is_a?(SymbolLiteral) && part.comments.empty?
      end
    end

    # If we have an empty array that contains only comments, then we're going
    # to do some special printing to ensure they get indented correctly.
    def empty_with_comments?
      contents.nil? && lbracket.comments.any? &&
        lbracket.comments.none?(&:inline?)
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
    # Formats the optional splat of an array pattern.
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

    # [nil | VarRef | ConstPathRef] the optional constant wrapper
    attr_reader :constant

    # [Array[ Node ]] the regular positional arguments that this array
    # pattern is matching against
    attr_reader :requireds

    # [nil | VarField] the optional starred identifier that grabs up a list of
    # positional arguments
    attr_reader :rest

    # [Array[ Node ]] the list of positional arguments occurring after the
    # optional star if there is one
    attr_reader :posts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, requireds:, rest:, posts:, location:)
      @constant = constant
      @requireds = requireds
      @rest = rest
      @posts = posts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_aryptn(self)
    end

    def child_nodes
      [constant, *requireds, rest, *posts]
    end

    def copy(
      constant: nil,
      requireds: nil,
      rest: nil,
      posts: nil,
      location: nil
    )
      node =
        AryPtn.new(
          constant: constant || self.constant,
          requireds: requireds || self.requireds,
          rest: rest || self.rest,
          posts: posts || self.posts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      q.group do
        q.format(constant) if constant
        q.text("[")
        q.indent do
          q.breakable_empty

          parts = [*requireds]
          parts << RestFormatter.new(rest) if rest
          parts += posts

          q.seplist(parts) { |part| q.format(part) }
        end
        q.breakable_empty
        q.text("]")
      end
    end

    def ===(other)
      other.is_a?(AryPtn) && constant === other.constant &&
        ArrayMatch.call(requireds, other.requireds) && rest === other.rest &&
        ArrayMatch.call(posts, other.posts)
    end
  end

  # Determins if the following value should be indented or not.
  module AssignFormatting
    def self.skip_indent?(value)
      case value
      when ArrayLiteral, HashLiteral, Heredoc, Lambda, QSymbols, QWords,
           Symbols, Words
        true
      when CallNode
        skip_indent?(value.receiver)
      when DynaSymbol
        value.quote.start_with?("%s")
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

    # [Node] the expression to be assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, value:, location:)
      @target = target
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_assign(self)
    end

    def child_nodes
      [target, value]
    end

    def copy(target: nil, value: nil, location: nil)
      node =
        Assign.new(
          target: target || self.target,
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_space
            q.format(value)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(Assign) && target === other.target && value === other.value
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
  # In the above example, the would be two Assoc nodes.
  class Assoc < Node
    # [Node] the key of this pair
    attr_reader :key

    # [nil | Node] the value of this pair
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(key:, value:, location:)
      @key = key
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_assoc(self)
    end

    def child_nodes
      [key, value]
    end

    def copy(key: nil, value: nil, location: nil)
      node =
        Assoc.new(
          key: key || self.key,
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { key: key, value: value, location: location, comments: comments }
    end

    def format(q)
      if value.is_a?(HashLiteral)
        format_contents(q)
      else
        q.group { format_contents(q) }
      end
    end

    def ===(other)
      other.is_a?(Assoc) && key === other.key && value === other.value
    end

    private

    def format_contents(q)
      (q.parent || HashKeyFormatter::Identity.new).format_key(q, key)
      return unless value

      if key.comments.empty? && AssignFormatting.skip_indent?(value)
        q.text(" ")
        q.format(value)
      else
        q.indent do
          q.breakable_space
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
    # [nil | Node] the expression that is being splatted
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_assoc_splat(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        AssocSplat.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("**")
      q.format(value) if value
    end

    def ===(other)
      other.is_a?(AssocSplat) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_backref(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Backref.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Backref) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_backtick(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Backtick.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Backtick) && value === other.value
    end
  end

  # This module is responsible for formatting the assocs contained within a
  # hash or bare hash. It first determines if every key in the hash can use
  # labels. If it can, it uses labels. Otherwise it uses hash rockets.
  module HashKeyFormatter
    # Formats the keys of a hash literal using labels.
    class Labels
      LABEL = /\A[A-Za-z_](\w*[\w!?])?\z/.freeze

      def format_key(q, key)
        case key
        when Label
          q.format(key)
        when SymbolLiteral
          q.format(key.value)
          q.text(":")
        when DynaSymbol
          parts = key.parts

          if parts.length == 1 && (part = parts.first) &&
               part.is_a?(TStringContent) && part.value.match?(LABEL)
            q.format(part)
            q.text(":")
          else
            q.format(key)
            q.text(":")
          end
        end
      end
    end

    # Formats the keys of a hash literal using hash rockets.
    class Rockets
      def format_key(q, key)
        case key
        when Label
          q.text(":#{key.value.chomp(":")}")
        when DynaSymbol
          q.text(":")
          q.format(key)
        else
          q.format(key)
        end

        q.text(" =>")
      end
    end

    # When formatting a single assoc node without the context of the parent
    # hash, this formatter is used. It uses whatever is present in the node,
    # because there is nothing to be consistent with.
    class Identity
      def format_key(q, key)
        if key.is_a?(Label)
          q.format(key)
        else
          q.format(key)
          q.text(" =>")
        end
      end
    end

    def self.for(container)
      container.assocs.each do |assoc|
        if assoc.is_a?(AssocSplat)
          # Splat nodes do not impact the formatting choice.
        elsif assoc.value.nil?
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
          case assoc.key
          when Label, DynaSymbol
            # Here labels can be used.
          when SymbolLiteral
            # When attempting to convert a hash rocket into a hash label,
            # you need to take care because only certain patterns are
            # allowed. Ruby source says that they have to match keyword
            # arguments to methods, but don't specify what that is. After
            # some experimentation, it looks like it's:
            value = assoc.key.value.value

            if !value.match?(/^[_A-Za-z]/) || value.end_with?("=")
              return Rockets.new
            end
          else
            # If the value is anything else, we have to use hash rockets.
            return Rockets.new
          end
        end
      end

      Labels.new
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

    def initialize(assocs:, location:)
      @assocs = assocs
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_bare_assoc_hash(self)
    end

    def child_nodes
      assocs
    end

    def copy(assocs: nil, location: nil)
      node =
        BareAssocHash.new(
          assocs: assocs || self.assocs,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { assocs: assocs, location: location, comments: comments }
    end

    def format(q)
      q.seplist(assocs) { |assoc| q.format(assoc) }
    end

    def ===(other)
      other.is_a?(BareAssocHash) && ArrayMatch.call(assocs, other.assocs)
    end

    def format_key(q, key)
      @key_formatter ||=
        case q.parents.take(3).last
        when Break, Next, ReturnNode
          HashKeyFormatter::Identity.new
        else
          HashKeyFormatter.for(self)
        end

      @key_formatter.format_key(q, key)
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

    def initialize(bodystmt:, location:)
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_begin(self)
    end

    def child_nodes
      [bodystmt]
    end

    def copy(bodystmt: nil, location: nil)
      node =
        Begin.new(
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { bodystmt: bodystmt, location: location, comments: comments }
    end

    def format(q)
      q.text("begin")

      unless bodystmt.empty?
        q.indent do
          q.breakable_force unless bodystmt.statements.empty?
          q.format(bodystmt)
        end
      end

      q.breakable_force
      q.text("end")
    end

    def ===(other)
      other.is_a?(Begin) && bodystmt === other.bodystmt
    end
  end

  # PinnedBegin represents a pinning a nested statement within pattern matching.
  #
  #     case value
  #     in ^(statement)
  #     end
  #
  class PinnedBegin < Node
    # [Node] the expression being pinned
    attr_reader :statement

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, location:)
      @statement = statement
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_pinned_begin(self)
    end

    def child_nodes
      [statement]
    end

    def copy(statement: nil, location: nil)
      node =
        PinnedBegin.new(
          statement: statement || self.statement,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { statement: statement, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("^(")
        q.nest(1) do
          q.indent do
            q.breakable_empty
            q.format(statement)
          end
          q.breakable_empty
          q.text(")")
        end
      end
    end

    def ===(other)
      other.is_a?(PinnedBegin) && statement === other.statement
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
    # Since Binary's operator is a symbol, it's better to use the `name` method
    # than to allocate a new string every time. This is a tiny performance
    # optimization, but enough that it shows up in the profiler. Adding this in
    # for older Ruby versions.
    unless :+.respond_to?(:name)
      using Module.new {
              refine Symbol do
                def name
                  to_s.freeze
                end
              end
            }
    end

    # [Node] the left-hand side of the expression
    attr_reader :left

    # [Symbol] the operator used between the two expressions
    attr_reader :operator

    # [Node] the right-hand side of the expression
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, operator:, right:, location:)
      @left = left
      @operator = operator
      @right = right
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_binary(self)
    end

    def child_nodes
      [left, right]
    end

    def copy(left: nil, operator: nil, right: nil, location: nil)
      node =
        Binary.new(
          left: left || self.left,
          operator: operator || self.operator,
          right: right || self.right,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        left: left,
        operator: operator,
        right: right,
        location: location,
        comments: comments
      }
    end

    def format(q)
      left = self.left
      power = operator == :**

      q.group do
        q.group { q.format(left) }
        q.text(" ") unless power

        if operator != :<<
          q.group do
            q.text(operator.name)
            q.indent do
              power ? q.breakable_empty : q.breakable_space
              q.format(right)
            end
          end
        elsif left.is_a?(Binary) && left.operator == :<<
          q.group do
            q.text(operator.name)
            q.indent do
              power ? q.breakable_empty : q.breakable_space
              q.format(right)
            end
          end
        else
          q.text("<< ")
          q.format(right)
        end
      end
    end

    def ===(other)
      other.is_a?(Binary) && left === other.left &&
        operator === other.operator && right === other.right
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

    def initialize(params:, locals:, location:)
      @params = params
      @locals = locals
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_block_var(self)
    end

    def child_nodes
      [params, *locals]
    end

    def copy(params: nil, locals: nil, location: nil)
      node =
        BlockVar.new(
          params: params || self.params,
          locals: locals || self.locals,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { params: params, locals: locals, location: location, comments: comments }
    end

    # Within the pipes of the block declaration, we don't want any spaces. So
    # we'll separate the parameters with a comma and space but no breakables.
    class Separator
      def call(q)
        q.text(", ")
      end
    end

    # We'll keep a single instance of this separator around for all block vars
    # to cut down on allocations.
    SEPARATOR = Separator.new.freeze

    def format(q)
      q.text("|")
      q.group do
        q.remove_breaks(q.format(params))

        if locals.any?
          q.text("; ")
          q.seplist(locals, SEPARATOR) { |local| q.format(local) }
        end
      end
      q.text("|")
    end

    def ===(other)
      other.is_a?(BlockVar) && params === other.params &&
        ArrayMatch.call(locals, other.locals)
    end

    # When a single required parameter is declared for a block, it gets
    # automatically expanded if the values being yielded into it are an array.
    def arg0?
      params.requireds.length == 1 && params.optionals.empty? &&
        params.rest.nil? && params.posts.empty? && params.keywords.empty? &&
        params.keyword_rest.nil? && params.block.nil?
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

    def initialize(name:, location:)
      @name = name
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_blockarg(self)
    end

    def child_nodes
      [name]
    end

    def copy(name: nil, location: nil)
      node =
        BlockArg.new(
          name: name || self.name,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("&")
      q.format(name) if name
    end

    def ===(other)
      other.is_a?(BlockArg) && name === other.name
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
      location:
    )
      @statements = statements
      @rescue_clause = rescue_clause
      @else_keyword = else_keyword
      @else_clause = else_clause
      @ensure_clause = ensure_clause
      @location = location
      @comments = []
    end

    def bind(parser, start_char, start_column, end_char, end_column)
      rescue_clause = self.rescue_clause

      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          start_column: start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )

      # Here we're going to determine the bounds for the statements
      consequent = rescue_clause || else_clause || ensure_clause
      statements.bind(
        parser,
        start_char,
        start_column,
        consequent ? consequent.location.start_char : end_char,
        consequent ? consequent.location.start_column : end_column
      )

      # Next we're going to determine the rescue clause if there is one
      if rescue_clause
        consequent = else_clause || ensure_clause

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

    def copy(
      statements: nil,
      rescue_clause: nil,
      else_keyword: nil,
      else_clause: nil,
      ensure_clause: nil,
      location: nil
    )
      node =
        BodyStmt.new(
          statements: statements || self.statements,
          rescue_clause: rescue_clause || self.rescue_clause,
          else_keyword: else_keyword || self.else_keyword,
          else_clause: else_clause || self.else_clause,
          ensure_clause: ensure_clause || self.ensure_clause,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        statements: statements,
        rescue_clause: rescue_clause,
        else_keyword: else_keyword,
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
            q.breakable_force
            q.format(rescue_clause)
          end
        end

        if else_clause
          q.nest(-2) do
            q.breakable_force
            q.format(else_keyword)
          end

          unless else_clause.empty?
            q.breakable_force
            q.format(else_clause)
          end
        end

        if ensure_clause
          q.nest(-2) do
            q.breakable_force
            q.format(ensure_clause)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(BodyStmt) && statements === other.statements &&
        rescue_clause === other.rescue_clause &&
        else_keyword === other.else_keyword &&
        else_clause === other.else_clause &&
        ensure_clause === other.ensure_clause
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
      # If there are no arguments associated with this flow control, then we can
      # safely just print the keyword and return.
      if node.arguments.nil?
        q.text(keyword)
        return
      end

      q.group do
        q.text(keyword)

        parts = node.arguments.parts
        length = parts.length

        if length == 0
          # Here there are no arguments at all, so we're not going to print
          # anything. This would be like if we had:
          #
          #     break
          #
        elsif length >= 2
          # If there are multiple arguments, format them all. If the line is
          # going to break into multiple, then use brackets to start and end the
          # expression.
          format_arguments(q, " [", "]")
        else
          # If we get here, then we're formatting a single argument to the flow
          # control keyword.
          part = parts.first

          case part
          when Paren
            statements = part.contents.body

            if statements.length == 1
              statement = statements.first

              if statement.is_a?(ArrayLiteral)
                contents = statement.contents

                if contents && contents.parts.length >= 2
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
                q.format(part)
              end
            else
              q.format(part)
            end
          when ArrayLiteral
            contents = part.contents

            if contents && contents.parts.length >= 2
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
              format_array_contents(q, part)
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
              q.format(part)
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
    end

    private

    def format_array_contents(q, array)
      q.if_break { q.text("[") }
      q.indent do
        q.breakable_empty
        q.format(array.contents)
      end
      q.breakable_empty
      q.if_break { q.text("]") }
    end

    def format_arguments(q, opening, closing)
      q.if_break { q.text(opening) }
      q.indent do
        q.breakable_space
        q.format(node.arguments)
      end
      q.breakable_empty
      q.if_break { q.text(closing) }
    end

    def skip_parens?(node)
      case node
      when FloatLiteral, Imaginary, Int, RationalLiteral
        true
      when VarRef
        case node.value
        when Const, CVar, GVar, IVar, Kw
          true
        else
          false
        end
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

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_break(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        Break.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("break", self).format(q)
    end

    def ===(other)
      other.is_a?(Break) && arguments === other.arguments
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
      case operator
      when :"::"
        q.text(".")
      when Op
        operator.value == "::" ? q.text(".") : operator.format(q)
      else
        operator.format(q)
      end
    end
  end

  # This is probably the most complicated formatter in this file. It's
  # responsible for formatting chains of method calls, with or without arguments
  # or blocks. In general, we want to go from something like
  #
  #     foo.bar.baz
  #
  # to
  #
  #     foo
  #       .bar
  #       .baz
  #
  # Of course there are a lot of caveats to that, including trailing operators
  # when necessary, where comments are places, how blocks are aligned, etc.
  class CallChainFormatter
    # [CallNode | MethodAddBlock] the top of the call chain
    attr_reader :node

    def initialize(node)
      @node = node
    end

    def format(q)
      children = [node]
      threshold = 3

      # First, walk down the chain until we get to the point where we're not
      # longer at a chainable node.
      loop do
        case (child = children.last)
        when CallNode
          case (receiver = child.receiver)
          when CallNode
            if receiver.receiver.nil?
              break
            else
              children << receiver
            end
          when MethodAddBlock
            if (call = receiver.call).is_a?(CallNode) && !call.receiver.nil?
              children << receiver
            else
              break
            end
          else
            break
          end
        when MethodAddBlock
          if (call = child.call).is_a?(CallNode) && !call.receiver.nil?
            children << call
          else
            break
          end
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
      if (parent = parents[2])
        # If we're at a block with the `do` keywords, then we want to go one
        # more level up. This is because do blocks have BodyStmt nodes instead
        # of just Statements nodes.
        parent = parents[3] if parent.is_a?(BlockNode) && parent.keywords?

        if parent.is_a?(MethodAddBlock) &&
             (call = parent.call).is_a?(CallNode) && call.message.value == "sig"
          threshold = 2
        end
      end

      if children.length >= threshold
        q.group do
          q
            .if_break { format_chain(q, children) }
            .if_flat { node.format_contents(q) }
        end
      else
        node.format_contents(q)
      end
    end

    def format_chain(q, children)
      # We're going to have some specialized behavior for if it's an entire
      # chain of calls without arguments except for the last one. This is common
      # enough in Ruby source code that it's worth the extra complexity here.
      empty_except_last =
        children
          .drop(1)
          .all? { |child| child.is_a?(CallNode) && child.arguments.nil? }

      # Here, we're going to add all of the children onto the stack of the
      # formatter so it's as if we had descending normally into them. This is
      # necessary so they can check their parents as normal.
      q.stack.concat(children)
      q.format(children.last.receiver) if children.last.receiver

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

          while (child = children.pop)
            if child.is_a?(CallNode)
              if (receiver = child.receiver).is_a?(CallNode) &&
                   (receiver.message != :call) &&
                   (receiver.message.value == "where") &&
                   (child.message != :call && child.message.value == "not")
                # This is very specialized behavior wherein we group
                # .where.not calls together because it looks better. For more
                # information, see
                # https://github.com/prettier/plugin-ruby/issues/862.
              else
                # If we're at a Call node and not a MethodAddBlock node in the
                # chain then we're going to add a newline so it indents
                # properly.
                q.breakable_empty
              end
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
            last_child = children.last
            if last_child.is_a?(CallNode) && last_child.message != :call &&
                 (
                   (last_child.message.comments.any? && last_child.operator) ||
                     (last_child.operator && last_child.operator.comments.any?)
                 )
              q.format(CallOperatorFormatter.new(last_child.operator))
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
        when CallNode
          node.format_arguments(q)
        when MethodAddBlock
          q.format(node.block)
        end
      end
    end

    def self.chained?(node)
      return false if ENV["STREE_FAST_FORMAT"]

      case node
      when CallNode
        !node.receiver.nil?
      when MethodAddBlock
        call = node.call
        call.is_a?(CallNode) && !call.receiver.nil?
      else
        false
      end
    end

    private

    # For certain nodes, we want to attach directly to the end and don't
    # want to indent the first call. So we'll pop off the first children and
    # format it separately here.
    def attach_directly?(node)
      case node.receiver
      when ArrayLiteral, HashLiteral, Heredoc, IfNode, UnlessNode,
           XStringLiteral
        true
      else
        false
      end
    end

    def format_child(
      q,
      child,
      skip_comments: false,
      skip_operator: false,
      skip_attached: false
    )
      # First, format the actual contents of the child.
      case child
      when CallNode
        q.group do
          if !skip_operator && child.operator
            q.format(CallOperatorFormatter.new(child.operator))
          end
          q.format(child.message) if child.message != :call
          child.format_arguments(q) unless skip_attached
        end
      when MethodAddBlock
        q.format(child.block) unless skip_attached
      end

      # If there are any comments on this node then we need to explicitly print
      # them out here since we're bypassing the normal comment printing.
      if child.comments.any? && !skip_comments
        child.comments.each do |comment|
          comment.inline? ? q.text(" ") : q.breakable_space
          comment.format(q)
        end

        q.break_parent
      end
    end
  end

  # CallNode represents a method call.
  #
  #     receiver.message
  #
  class CallNode < Node
    # [nil | Node] the receiver of the method call
    attr_reader :receiver

    # [nil | :"::" | Op | Period] the operator being used to send the message
    attr_reader :operator

    # [:call | Backtick | Const | Ident | Op] the message being sent
    attr_reader :message

    # [nil | ArgParen | Args] the arguments to the method call
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(receiver:, operator:, message:, arguments:, location:)
      @receiver = receiver
      @operator = operator
      @message = message
      @arguments = arguments
      @location = location
      @comments = []
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

    def copy(
      receiver: nil,
      operator: nil,
      message: nil,
      arguments: nil,
      location: nil
    )
      node =
        CallNode.new(
          receiver: receiver || self.receiver,
          operator: operator || self.operator,
          message: message || self.message,
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      if receiver
        # If we're at the top of a call chain, then we're going to do some
        # specialized printing in case we can print it nicely. We _only_ do this
        # at the top of the chain to avoid weird recursion issues.
        if CallChainFormatter.chained?(receiver) &&
             !CallChainFormatter.chained?(q.parent)
          q.group do
            q
              .if_break { CallChainFormatter.new(self).format(q) }
              .if_flat { format_contents(q) }
          end
        else
          format_contents(q)
        end
      else
        q.format(message)

        # Note that this explicitly leaves parentheses in place even if they are
        # empty. There are two reasons we would need to do this. The first is if
        # we're calling something that looks like a constant, as in:
        #
        #     Foo()
        #
        # In this case if we remove the parentheses then this becomes a constant
        # reference and not a method call. The second is if we're calling a
        # method that is the same name as a local variable that is in scope, as
        # in:
        #
        #     foo = foo()
        #
        # In this case we have to keep the parentheses or else it treats this
        # like assigning nil to the local variable. Note that we could attempt
        # to be smarter about this by tracking the local variables that are in
        # scope, but for now it's simpler and more efficient to just leave the
        # parentheses in place.
        q.format(arguments) if arguments
      end
    end

    def ===(other)
      other.is_a?(CallNode) && receiver === other.receiver &&
        operator === other.operator && message === other.message &&
        arguments === other.arguments
    end

    # Print out the arguments to this call. If there are no arguments, then do
    # nothing.
    def format_arguments(q)
      case arguments
      when ArgParen
        q.format(arguments)
      when Args
        q.text(" ")
        q.format(arguments)
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
              q.breakable_force
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

    def arity
      arguments&.arity || 0
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

    # [nil | Node] optional value being switched on
    attr_reader :value

    # [In | When] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, value:, consequent:, location:)
      @keyword = keyword
      @value = value
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_case(self)
    end

    def child_nodes
      [keyword, value, consequent]
    end

    def copy(keyword: nil, value: nil, consequent: nil, location: nil)
      node =
        Case.new(
          keyword: keyword || self.keyword,
          value: value || self.value,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

        q.breakable_force
        q.format(consequent)
        q.breakable_force

        q.text("end")
      end
    end

    def ===(other)
      other.is_a?(Case) && keyword === other.keyword && value === other.value &&
        consequent === other.consequent
    end
  end

  # RAssign represents a single-line pattern match.
  #
  #     value in pattern
  #     value => pattern
  #
  class RAssign < Node
    # [Node] the left-hand expression
    attr_reader :value

    # [Kw | Op] the operator being used to match against the pattern, which is
    # either => or in
    attr_reader :operator

    # [Node] the pattern on the right-hand side of the expression
    attr_reader :pattern

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, operator:, pattern:, location:)
      @value = value
      @operator = operator
      @pattern = pattern
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_rassign(self)
    end

    def child_nodes
      [value, operator, pattern]
    end

    def copy(value: nil, operator: nil, pattern: nil, location: nil)
      node =
        RAssign.new(
          value: value || self.value,
          operator: operator || self.operator,
          pattern: pattern || self.pattern,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

        case pattern
        when AryPtn, FndPtn, HshPtn
          q.text(" ")
          q.format(pattern)
        else
          q.group do
            q.indent do
              q.breakable_space
              q.format(pattern)
            end
          end
        end
      end
    end

    def ===(other)
      other.is_a?(RAssign) && value === other.value &&
        operator === other.operator && pattern === other.pattern
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

    # [nil | Node] the optional superclass declaration
    attr_reader :superclass

    # [BodyStmt] the expressions to execute within the context of the class
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, superclass:, bodystmt:, location:)
      @constant = constant
      @superclass = superclass
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_class(self)
    end

    def child_nodes
      [constant, superclass, bodystmt]
    end

    def copy(constant: nil, superclass: nil, bodystmt: nil, location: nil)
      node =
        ClassDeclaration.new(
          constant: constant || self.constant,
          superclass: superclass || self.superclass,
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        constant: constant,
        superclass: superclass,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      if bodystmt.empty?
        q.group do
          format_declaration(q)
          q.breakable_force
          q.text("end")
        end
      else
        q.group do
          format_declaration(q)

          q.indent do
            q.breakable_force
            q.format(bodystmt)
          end

          q.breakable_force
          q.text("end")
        end
      end
    end

    def ===(other)
      other.is_a?(ClassDeclaration) && constant === other.constant &&
        superclass === other.superclass && bodystmt === other.bodystmt
    end

    private

    def format_declaration(q)
      q.group do
        q.text("class ")
        q.format(constant)

        if superclass
          q.text(" < ")
          q.format(superclass)
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

    def copy(value: nil, location: nil)
      Comma.new(value: value || self.value, location: location || self.location)
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(Comma) && value === other.value
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

    # [nil | BlockNode] the optional block being passed to the method
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(message:, arguments:, block:, location:)
      @message = message
      @arguments = arguments
      @block = block
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_command(self)
    end

    def child_nodes
      [message, arguments, block]
    end

    def copy(message: nil, arguments: nil, block: nil, location: nil)
      node =
        Command.new(
          message: message || self.message,
          arguments: arguments || self.arguments,
          block: block || self.block,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        message: message,
        arguments: arguments,
        block: block,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.group do
        q.format(message)
        align(q, self) { q.format(arguments) }
      end

      q.format(block) if block
    end

    def ===(other)
      other.is_a?(Command) && message === other.message &&
        arguments === other.arguments && block === other.block
    end

    def arity
      arguments.arity
    end

    private

    def align(q, node, &block)
      arguments = node.arguments

      if arguments.is_a?(Args)
        parts = arguments.parts

        if parts.size == 1
          part = parts.first

          case part
          when DefNode
            q.text(" ")
            yield
          when IfOp
            q.if_flat { q.text(" ") }
            yield
          when Command
            align(q, part, &block)
          else
            q.text(" ")
            q.nest(message.value.length + 1) { yield }
          end
        else
          q.text(" ")
          q.nest(message.value.length + 1) { yield }
        end
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
    # [nil | Node] the receiver of the message
    attr_reader :receiver

    # [nil | :"::" | Op | Period] the operator used to send the message
    attr_reader :operator

    # [:call | Const | Ident | Op] the message being send
    attr_reader :message

    # [nil | Args | ArgParen] the arguments going along with the message
    attr_reader :arguments

    # [nil | BlockNode] the block associated with this method call
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      receiver:,
      operator:,
      message:,
      arguments:,
      block:,
      location:
    )
      @receiver = receiver
      @operator = operator
      @message = message
      @arguments = arguments
      @block = block
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_command_call(self)
    end

    def child_nodes
      [receiver, message, arguments, block]
    end

    def copy(
      receiver: nil,
      operator: nil,
      message: nil,
      arguments: nil,
      block: nil,
      location: nil
    )
      node =
        CommandCall.new(
          receiver: receiver || self.receiver,
          operator: operator || self.operator,
          message: message || self.message,
          arguments: arguments || self.arguments,
          block: block || self.block,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        block: block,
        location: location,
        comments: comments
      }
    end

    def format(q)
      message = self.message
      arguments = self.arguments
      block = self.block

      q.group do
        doc =
          q.nest(0) do
            q.format(receiver)

            # If there are leading comments on the message then we know we have
            # a newline in the source that is forcing these things apart. In
            # this case we will have to use a trailing operator.
            if message != :call && message.comments.any?(&:leading?)
              q.format(CallOperatorFormatter.new(operator), stackable: false)
              q.indent do
                q.breakable_empty
                q.format(message)
              end
            else
              q.format(CallOperatorFormatter.new(operator), stackable: false)
              q.format(message)
            end
          end

        # Format the arguments for this command call here. If there are no
        # arguments, then print nothing.
        if arguments
          parts = arguments.parts

          if parts.length == 1 && parts.first.is_a?(IfOp)
            q.if_flat { q.text(" ") }
            q.format(arguments)
          else
            q.text(" ")
            q.nest(argument_alignment(q, doc)) { q.format(arguments) }
          end
        end
      end

      q.format(block) if block
    end

    def ===(other)
      other.is_a?(CommandCall) && receiver === other.receiver &&
        operator === other.operator && message === other.message &&
        arguments === other.arguments && block === other.block
    end

    def arity
      arguments&.arity || 0
    end

    private

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
        width = q.last_position(doc) + 1
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
      value.match?(/\A#\s*stree-ignore\s*\z/)
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

    def copy(value: nil, inline: nil, location: nil)
      Comment.new(
        value: value || self.value,
        inline: inline || self.inline,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, inline: inline, location: location }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Comment) && value === other.value && inline === other.inline
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_const(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Const.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Const) && value === other.value
    end
  end

  # ConstPathField represents the child node of some kind of assignment. It
  # represents when you're assigning to a constant that is being referenced as
  # a child of another variable.
  #
  #     object::Const = value
  #
  class ConstPathField < Node
    # [Node] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, constant:, location:)
      @parent = parent
      @constant = constant
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_const_path_field(self)
    end

    def child_nodes
      [parent, constant]
    end

    def copy(parent: nil, constant: nil, location: nil)
      node =
        ConstPathField.new(
          parent: parent || self.parent,
          constant: constant || self.constant,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(ConstPathField) && parent === other.parent &&
        constant === other.constant
    end
  end

  # ConstPathRef represents referencing a constant by a path.
  #
  #     object::Const
  #
  class ConstPathRef < Node
    # [Node] the source of the constant
    attr_reader :parent

    # [Const] the constant itself
    attr_reader :constant

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, constant:, location:)
      @parent = parent
      @constant = constant
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_const_path_ref(self)
    end

    def child_nodes
      [parent, constant]
    end

    def copy(parent: nil, constant: nil, location: nil)
      node =
        ConstPathRef.new(
          parent: parent || self.parent,
          constant: constant || self.constant,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(ConstPathRef) && parent === other.parent &&
        constant === other.constant
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

    def initialize(constant:, location:)
      @constant = constant
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_const_ref(self)
    end

    def child_nodes
      [constant]
    end

    def copy(constant: nil, location: nil)
      node =
        ConstRef.new(
          constant: constant || self.constant,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.format(constant)
    end

    def ===(other)
      other.is_a?(ConstRef) && constant === other.constant
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_cvar(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        CVar.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(CVar) && value === other.value
    end
  end

  # Def represents defining a regular method on the current self object.
  #
  #     def method(param) result end
  #     def object.method(param) result end
  #
  class DefNode < Node
    # [nil | Node] the target where the method is being defined
    attr_reader :target

    # [nil | Op | Period] the operator being used to declare the method
    attr_reader :operator

    # [Backtick | Const | Ident | Kw | Op] the name of the method
    attr_reader :name

    # [nil | Params | Paren] the parameter declaration for the method
    attr_reader :params

    # [BodyStmt | Node] the expressions to be executed by the method
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, operator:, name:, params:, bodystmt:, location:)
      @target = target
      @operator = operator
      @name = name
      @params = params
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_def(self)
    end

    def child_nodes
      [target, operator, name, params, bodystmt]
    end

    def copy(
      target: nil,
      operator: nil,
      name: nil,
      params: nil,
      bodystmt: nil,
      location: nil
    )
      node =
        DefNode.new(
          target: target || self.target,
          operator: operator || self.operator,
          name: name || self.name,
          params: params || self.params,
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      params = self.params
      bodystmt = self.bodystmt

      q.group do
        q.group do
          q.text("def")
          q.text(" ") if target || name.comments.empty?

          if target
            q.format(target)
            q.format(CallOperatorFormatter.new(operator), stackable: false)
          end

          q.format(name)

          case params
          when Paren
            q.format(params)
          when Params
            q.format(params) if !params.empty? || params.comments.any?
          end
        end

        if endless?
          q.text(" =")
          q.group do
            q.indent do
              q.breakable_space
              q.format(bodystmt)
            end
          end
        else
          unless bodystmt.empty?
            q.indent do
              q.breakable_force
              q.format(bodystmt)
            end
          end

          q.breakable_force
          q.text("end")
        end
      end
    end

    def ===(other)
      other.is_a?(DefNode) && target === other.target &&
        operator === other.operator && name === other.name &&
        params === other.params && bodystmt === other.bodystmt
    end

    # Returns true if the method was found in the source in the "endless" form,
    # i.e. where the method body is defined using the `=` operator after the
    # method name and parameters.
    def endless?
      !bodystmt.is_a?(BodyStmt)
    end

    def arity
      params = self.params

      case params
      when Params
        params.arity
      when Paren
        params.contents.arity
      else
        0..0
      end
    end
  end

  # Defined represents the use of the +defined?+ operator. It can be used with
  # and without parentheses.
  #
  #     defined?(variable)
  #
  class Defined < Node
    # [Node] the value being sent to the keyword
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_defined(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        Defined.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text("defined?(")
      q.group do
        q.indent do
          q.breakable_empty
          q.format(value)
        end
        q.breakable_empty
      end
      q.text(")")
    end

    def ===(other)
      other.is_a?(Defined) && value === other.value
    end
  end

  # Block represents passing a block to a method call using the +do+ and +end+
  # keywords or the +{+ and +}+ operators.
  #
  #     method do |value|
  #     end
  #
  #     method { |value| }
  #
  class BlockNode < Node
    # Formats the opening brace or keyword of a block.
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

    # [LBrace | Kw] the left brace or the do keyword that opens this block
    attr_reader :opening

    # [nil | BlockVar] the optional variable declaration within this block
    attr_reader :block_var

    # [BodyStmt | Statements] the expressions to be executed within this block
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(opening:, block_var:, bodystmt:, location:)
      @opening = opening
      @block_var = block_var
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_block(self)
    end

    def child_nodes
      [opening, block_var, bodystmt]
    end

    def copy(opening: nil, block_var: nil, bodystmt: nil, location: nil)
      node =
        BlockNode.new(
          opening: opening || self.opening,
          block_var: block_var || self.block_var,
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        opening: opening,
        block_var: block_var,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      # If this is nested anywhere inside of a Command or CommandCall node, then
      # we can't change which operators we're using for the bounds of the block.
      break_opening, break_closing, flat_opening, flat_closing =
        if unchangeable_bounds?(q)
          block_close = keywords? ? "end" : "}"
          [opening.value, block_close, opening.value, block_close]
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
      case q.parent
      when nil, Command, CommandCall
        q.break_parent
        format_break(q, break_opening, break_closing)
        return
      end

      q.group do
        q
          .if_break { format_break(q, break_opening, break_closing) }
          .if_flat { format_flat(q, flat_opening, flat_closing) }
      end
    end

    def ===(other)
      other.is_a?(BlockNode) && opening === other.opening &&
        block_var === other.block_var && bodystmt === other.bodystmt
    end

    def keywords?
      opening.is_a?(Kw)
    end

    def arity
      case block_var
      when BlockVar
        block_var.params.arity
      else
        0..0
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
        case parent
        when Statements, ArgParen
          break false
        when Command, CommandCall
          true
        else
          false
        end
      end
    end

    # If we're a sibling of a control-flow keyword, then we're going to have to
    # use the do..end bounds.
    def forced_do_end_bounds?(q)
      case q.parent&.call
      when Break, Next, ReturnNode, Super
        true
      else
        false
      end
    end

    # If we're the predicate of a loop or conditional, then we're going to have
    # to go with the {..} bounds.
    def forced_brace_bounds?(q)
      previous = nil
      q.parents.any? do |parent|
        case parent
        when Paren, Statements
          # If we hit certain breakpoints then we know we're safe.
          return false
        when IfNode, IfOp, UnlessNode, WhileNode, UntilNode
          return true if parent.predicate == previous
        end

        previous = parent
        false
      end
    end

    def format_break(q, break_opening, break_closing)
      q.text(" ")
      q.format(BlockOpenFormatter.new(break_opening, opening), stackable: false)

      if block_var
        q.text(" ")
        q.format(block_var)
      end

      unless bodystmt.empty?
        q.indent do
          q.breakable_space
          q.format(bodystmt)
        end
      end

      q.breakable_space
      q.text(break_closing)
    end

    def format_flat(q, flat_opening, flat_closing)
      q.text(" ")
      q.format(BlockOpenFormatter.new(flat_opening, opening), stackable: false)

      if block_var
        q.breakable_space
        q.format(block_var)
        q.breakable_space
      end

      if bodystmt.empty?
        q.text(" ") if flat_opening == "do"
      else
        q.breakable_space unless block_var
        q.format(bodystmt)
        q.breakable_space
      end

      q.text(flat_closing)
    end
  end

  # RangeNode represents using the .. or the ... operator between two
  # expressions. Usually this is to create a range object.
  #
  #     1..2
  #
  # Sometimes this operator is used to create a flip-flop.
  #
  #     if value == 5 .. value == 10
  #     end
  #
  # One of the sides of the expression may be nil, but not both.
  class RangeNode < Node
    # [nil | Node] the left side of the expression
    attr_reader :left

    # [Op] the operator used for this range
    attr_reader :operator

    # [nil | Node] the right side of the expression
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, operator:, right:, location:)
      @left = left
      @operator = operator
      @right = right
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_range(self)
    end

    def child_nodes
      [left, right]
    end

    def copy(left: nil, operator: nil, right: nil, location: nil)
      node =
        RangeNode.new(
          left: left || self.left,
          operator: operator || self.operator,
          right: right || self.right,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        left: left,
        operator: operator,
        right: right,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.format(left) if left

      case q.parent
      when IfNode, UnlessNode
        q.text(" #{operator.value} ")
      else
        q.text(operator.value)
      end

      q.format(right) if right
    end

    def ===(other)
      other.is_a?(RangeNode) && left === other.left &&
        operator === other.operator && right === other.right
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
    def self.locked?(node, quote)
      node.parts.any? do |part|
        !part.is_a?(TStringContent) || part.value.match?(/\\|#[@${]|#{quote}/)
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

    # [nil | String] the quote used to delimit the dynamic symbol
    attr_reader :quote

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, quote:, location:)
      @parts = parts
      @quote = quote
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_dyna_symbol(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, quote: nil, location: nil)
      node =
        DynaSymbol.new(
          parts: parts || self.parts,
          quote: quote || self.quote,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, quote: quote, location: location, comments: comments }
    end

    def format(q)
      opening_quote, closing_quote = quotes(q)

      q.text(opening_quote)
      q.group do
        parts.each do |part|
          if part.is_a?(TStringContent)
            value = Quotes.normalize(part.value, closing_quote)
            first = true

            value.each_line(chomp: true) do |line|
              if first
                first = false
              else
                q.breakable_return
              end

              q.text(line)
            end

            q.breakable_return if value.end_with?("\n")
          else
            q.format(part)
          end
        end
      end
      q.text(closing_quote)
    end

    def ===(other)
      other.is_a?(DynaSymbol) && ArrayMatch.call(parts, other.parts) &&
        quote === other.quote
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

        # This check is to ensure we don't find a matching quote inside of the
        # symbol that would be confusing.
        matched =
          parts.any? do |part|
            part.is_a?(TStringContent) && part.value.match?(pattern)
          end

        if matched
          [quote, matching]
        elsif Quotes.locked?(self, q.quote)
          ["#{":" unless hash_key}'", "'"]
        else
          ["#{":" unless hash_key}#{q.quote}", q.quote]
        end
      elsif Quotes.locked?(self, q.quote)
        if quote.start_with?(":")
          [hash_key ? quote[1..] : quote, quote[1..]]
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

    def initialize(keyword:, statements:, location:)
      @keyword = keyword
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_else(self)
    end

    def child_nodes
      [keyword, statements]
    end

    def copy(keyword: nil, statements: nil, location: nil)
      node =
        Else.new(
          keyword: keyword || self.keyword,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_force
            q.format(statements)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(Else) && keyword === other.keyword &&
        statements === other.statements
    end
  end

  # Elsif represents another clause in an +if+ or +unless+ chain.
  #
  #     if variable
  #     elsif other_variable
  #     end
  #
  class Elsif < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Elsif | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_elsif(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    def copy(predicate: nil, statements: nil, consequent: nil, location: nil)
      node =
        Elsif.new(
          predicate: predicate || self.predicate,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_force
            q.format(statements)
          end
        end

        if consequent
          q.group do
            q.breakable_force
            q.format(consequent)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(Elsif) && predicate === other.predicate &&
        statements === other.statements && consequent === other.consequent
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

    def copy(value: nil, location: nil)
      EmbDoc.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def format(q)
      if (q.parent.is_a?(DefNode) && q.parent.endless?) ||
           q.parent.is_a?(Statements)
        q.trim
      else
        q.breakable_return
      end

      q.text(value)
    end

    def ===(other)
      other.is_a?(EmbDoc) && value === other.value
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

    def copy(value: nil, location: nil)
      EmbExprBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(EmbExprBeg) && value === other.value
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

    def copy(value: nil, location: nil)
      EmbExprEnd.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(EmbExprEnd) && value === other.value
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

    def copy(value: nil, location: nil)
      EmbVar.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(EmbVar) && value === other.value
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

    def initialize(keyword:, statements:, location:)
      @keyword = keyword
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_ensure(self)
    end

    def child_nodes
      [keyword, statements]
    end

    def copy(keyword: nil, statements: nil, location: nil)
      node =
        Ensure.new(
          keyword: keyword || self.keyword,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
          q.breakable_force
          q.format(statements)
        end
      end
    end

    def ===(other)
      other.is_a?(Ensure) && keyword === other.keyword &&
        statements === other.statements
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_excessed_comma(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        ExcessedComma.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(ExcessedComma) && value === other.value
    end
  end

  # Field is always the child of an assignment. It represents assigning to a
  # “field” on an object.
  #
  #     object.variable = value
  #
  class Field < Node
    # [Node] the parent object that owns the field being assigned
    attr_reader :parent

    # [:"::" | Op | Period] the operator being used for the assignment
    attr_reader :operator

    # [Const | Ident] the name of the field being assigned
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parent:, operator:, name:, location:)
      @parent = parent
      @operator = operator
      @name = name
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_field(self)
    end

    def child_nodes
      operator = self.operator
      [parent, (operator if operator != :"::"), name]
    end

    def copy(parent: nil, operator: nil, name: nil, location: nil)
      node =
        Field.new(
          parent: parent || self.parent,
          operator: operator || self.operator,
          name: name || self.name,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(Field) && parent === other.parent &&
        operator === other.operator && name === other.name
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_float(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        FloatLiteral.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(FloatLiteral) && value === other.value
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
    # [nil | VarRef | ConstPathRef] the optional constant wrapper
    attr_reader :constant

    # [VarField] the splat on the left-hand side
    attr_reader :left

    # [Array[ Node ]] the list of positional expressions in the pattern that
    # are being matched
    attr_reader :values

    # [VarField] the splat on the right-hand side
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, left:, values:, right:, location:)
      @constant = constant
      @left = left
      @values = values
      @right = right
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_fndptn(self)
    end

    def child_nodes
      [constant, left, *values, right]
    end

    def copy(constant: nil, left: nil, values: nil, right: nil, location: nil)
      node =
        FndPtn.new(
          constant: constant || self.constant,
          left: left || self.left,
          values: values || self.values,
          right: right || self.right,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

      q.group do
        q.text("[")

        q.indent do
          q.breakable_empty

          q.text("*")
          q.format(left)
          q.comma_breakable

          q.seplist(values) { |value| q.format(value) }
          q.comma_breakable

          q.text("*")
          q.format(right)
        end

        q.breakable_empty
        q.text("]")
      end
    end

    def ===(other)
      other.is_a?(FndPtn) && constant === other.constant &&
        left === other.left && ArrayMatch.call(values, other.values) &&
        right === other.right
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

    # [Node] the object being enumerated in the loop
    attr_reader :collection

    # [Statements] the statements to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(index:, collection:, statements:, location:)
      @index = index
      @collection = collection
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_for(self)
    end

    def child_nodes
      [index, collection, statements]
    end

    def copy(index: nil, collection: nil, statements: nil, location: nil)
      node =
        For.new(
          index: index || self.index,
          collection: collection || self.collection,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_force
            q.format(statements)
          end
        end

        q.breakable_force
        q.text("end")
      end
    end

    def ===(other)
      other.is_a?(For) && index === other.index &&
        collection === other.collection && statements === other.statements
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_gvar(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        GVar.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(GVar) && value === other.value
    end
  end

  # HashLiteral represents a hash literal.
  #
  #     { key => value }
  #
  class HashLiteral < Node
    # This is a special formatter used if the hash literal contains no values
    # but _does_ contain comments. In this case we do some special formatting to
    # make sure the comments gets indented properly.
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
              q.breakable_force
              comment.format(q)
            end
          end
          q.breakable_force
          q.text("}")
        end
      end
    end

    # [LBrace] the left brace that opens this hash
    attr_reader :lbrace

    # [Array[ Assoc | AssocSplat ]] the optional contents of the hash
    attr_reader :assocs

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lbrace:, assocs:, location:)
      @lbrace = lbrace
      @assocs = assocs
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_hash(self)
    end

    def child_nodes
      [lbrace].concat(assocs)
    end

    def copy(lbrace: nil, assocs: nil, location: nil)
      node =
        HashLiteral.new(
          lbrace: lbrace || self.lbrace,
          assocs: assocs || self.assocs,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { lbrace: lbrace, assocs: assocs, location: location, comments: comments }
    end

    def format(q)
      if q.parent.is_a?(Assoc)
        format_contents(q)
      else
        q.group { format_contents(q) }
      end
    end

    def ===(other)
      other.is_a?(HashLiteral) && lbrace === other.lbrace &&
        ArrayMatch.call(assocs, other.assocs)
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
        q.breakable_empty
      else
        q.indent do
          q.breakable_space
          q.seplist(assocs) { |assoc| q.format(assoc) }
          q.if_break { q.text(",") } if q.trailing_comma?
        end
        q.breakable_space
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

    # [HeredocEnd] the ending of the heredoc
    attr_reader :ending

    # [Integer] how far to dedent the heredoc
    attr_reader :dedent

    # [Array[ StringEmbExpr | StringDVar | TStringContent ]] the parts of the
    # heredoc string literal
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(beginning:, location:, ending: nil, dedent: 0, parts: [])
      @beginning = beginning
      @ending = ending
      @dedent = dedent
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_heredoc(self)
    end

    def child_nodes
      [beginning, *parts, ending]
    end

    def copy(beginning: nil, location: nil, ending: nil, parts: nil)
      node =
        Heredoc.new(
          beginning: beginning || self.beginning,
          location: location || self.location,
          ending: ending || self.ending,
          parts: parts || self.parts
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        beginning: beginning,
        location: location,
        ending: ending,
        parts: parts,
        comments: comments
      }
    end

    # This is a very specific behavior where you want to force a newline, but
    # don't want to force the break parent.
    SEPARATOR =
      PrettierPrint::Breakable.new(" ", 1, indent: false, force: true).freeze

    def format(q)
      q.group do
        q.format(beginning)

        q.line_suffix(priority: Formatter::HEREDOC_PRIORITY) do
          q.group do
            q.target << SEPARATOR

            parts.each do |part|
              if part.is_a?(TStringContent)
                value = part.value
                first = true

                value.each_line(chomp: true) do |line|
                  if first
                    first = false
                  else
                    q.target << SEPARATOR
                  end

                  q.text(line)
                end

                q.target << SEPARATOR if value.end_with?("\n")
              else
                q.format(part)
              end
            end

            q.format(ending)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(Heredoc) && beginning === other.beginning &&
        ending === other.ending && ArrayMatch.call(parts, other.parts)
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_heredoc_beg(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        HeredocBeg.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(HeredocBeg) && value === other.value
    end
  end

  # HeredocEnd represents the closing declaration of a heredoc.
  #
  #     <<~DOC
  #       contents
  #     DOC
  #
  # In the example above the HeredocEnd node represents the closing DOC.
  class HeredocEnd < Node
    # [String] the closing declaration of the heredoc
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_heredoc_end(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        HeredocEnd.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(HeredocEnd) && value === other.value
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
    # Formats a key-value pair in a hash pattern. The value is optional.
    class KeywordFormatter
      # [Label] the keyword being used
      attr_reader :key

      # [Node] the optional value for the keyword
      attr_reader :value

      def initialize(key, value)
        @key = key
        @value = value
      end

      def comments
        []
      end

      def format(q)
        HashKeyFormatter::Labels.new.format_key(q, key)

        if value
          q.text(" ")
          q.format(value)
        end
      end
    end

    # Formats the optional double-splat from the pattern.
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

    # [nil | VarRef | ConstPathRef] the optional constant wrapper
    attr_reader :constant

    # [Array[ [DynaSymbol | Label, nil | Node] ]] the set of tuples
    # representing the keywords that should be matched against in the pattern
    attr_reader :keywords

    # [nil | VarField] an optional parameter to gather up all remaining keywords
    attr_reader :keyword_rest

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(constant:, keywords:, keyword_rest:, location:)
      @constant = constant
      @keywords = keywords
      @keyword_rest = keyword_rest
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_hshptn(self)
    end

    def child_nodes
      [constant, *keywords.flatten(1), keyword_rest]
    end

    def copy(constant: nil, keywords: nil, keyword_rest: nil, location: nil)
      node =
        HshPtn.new(
          constant: constant || self.constant,
          keywords: keywords || self.keywords,
          keyword_rest: keyword_rest || self.keyword_rest,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      nested = PATTERNS.include?(q.parent.class)

      # If there is a constant, we're going to format to have the constant name
      # first and then use brackets.
      if constant
        q.group do
          q.format(constant)
          q.text("[")
          q.indent do
            q.breakable_empty
            format_contents(q, parts, nested)
          end
          q.breakable_empty
          q.text("]")
        end
        return
      end

      # If there's nothing at all, then we're going to use empty braces.
      if parts.empty?
        q.text("{}")
        return
      end

      # If there's only one pair, then we'll just print the contents provided
      # we're not inside another pattern.
      if !nested && parts.size == 1
        format_contents(q, parts, nested)
        return
      end

      # Otherwise, we're going to always use braces to make it clear it's a hash
      # pattern.
      q.group do
        q.text("{")
        q.indent do
          q.breakable_space
          format_contents(q, parts, nested)
        end

        if q.target_ruby_version < Formatter::SemanticVersion.new("2.7.3")
          q.text(" }")
        else
          q.breakable_space
          q.text("}")
        end
      end
    end

    def ===(other)
      other.is_a?(HshPtn) && constant === other.constant &&
        keywords.length == other.keywords.length &&
        keywords
          .zip(other.keywords)
          .all? { |left, right| ArrayMatch.call(left, right) } &&
        keyword_rest === other.keyword_rest
    end

    private

    def format_contents(q, parts, nested)
      keyword_rest = self.keyword_rest

      q.group { q.seplist(parts) { |part| q.format(part, stackable: false) } }

      # If there isn't a constant, and there's a blank keyword_rest, then we
      # have an plain ** that needs to have a `then` after it in order to
      # parse correctly on the next parse.
      if !constant && keyword_rest && keyword_rest.value.nil? && !nested
        q.text(" then")
      end
    end
  end

  # The list of nodes that represent patterns inside of pattern matching so that
  # when a pattern is being printed it knows if it's nested.
  PATTERNS = [AryPtn, Binary, FndPtn, HshPtn, RAssign].freeze

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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_ident(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Ident.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Ident) && value === other.value
    end
  end

  # If the predicate of a conditional or loop contains an assignment (in which
  # case we can't know for certain that that assignment doesn't impact the
  # statements inside the conditional) then we can't use the modifier form
  # and we must use the block form.
  module ContainsAssignment
    def self.call(parent)
      queue = [parent]

      while (node = queue.shift)
        case node
        when Assign, MAssign, OpAssign
          return true
        else
          node.child_nodes.each { |child| queue << child if child }
        end
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
        return false if ENV["STREE_FAST_FORMAT"] || q.disable_auto_ternary?

        # If this is a conditional inside of a parentheses as the only content,
        # then we don't want to transform it into a ternary. Presumably the user
        # wanted it to be an explicit conditional because there are parentheses
        # around it. So we'll just leave it in place.
        grandparent = q.grandparent
        if grandparent.is_a?(Paren) && (body = grandparent.contents.body) &&
             body.length == 1 && body.first == node
          return false
        end

        # Otherwise, we'll check the type of predicate. For certain nodes we
        # want to force it to not be a ternary, like if the predicate is an
        # assignment because it's hard to read.
        case node.predicate
        when Assign, Binary, Command, CommandCall, MAssign, OpAssign
          return false
        when Not
          return false unless node.predicate.parentheses?
        end

        # If there's no Else, then this can't be represented as a ternary.
        return false unless node.consequent.is_a?(Else)

        truthy_body = node.statements.body
        falsy_body = node.consequent.statements.body

        (truthy_body.length == 1) && ternaryable?(truthy_body.first) &&
          (falsy_body.length == 1) && ternaryable?(falsy_body.first)
      end

      private

      # Certain expressions cannot be reduced to a ternary without adding
      # parentheses around them. In this case we say they cannot be ternaried
      # and default instead to breaking them into multiple lines.
      def ternaryable?(statement)
        case statement
        when AliasNode, Assign, Break, Command, CommandCall, Defined, Heredoc,
             IfNode, IfOp, Lambda, MAssign, Next, OpAssign, RescueMod,
             ReturnNode, Super, Undef, UnlessNode, UntilNode, VoidStmt,
             WhileNode, YieldNode, ZSuper
          # This is a list of nodes that should not be allowed to be a part of a
          # ternary clause.
          false
        when Binary
          # If the user is using one of the lower precedence "and" or "or"
          # operators, then we can't use a ternary expression as it would break
          # the flow control.
          operator = statement.operator
          operator != :and && operator != :or
        else
          true
        end
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
      if node.modifier?
        statement = node.statements.body[0]

        if ContainsAssignment.call(statement) || q.parent.is_a?(In)
          q.group { format_flat(q) }
        else
          q.group do
            q
              .if_break { format_break(q, force: false) }
              .if_flat { format_flat(q) }
          end
        end
      else
        # If we can transform this node into a ternary, then we're going to
        # print a special version that uses the ternary operator if it fits on
        # one line.
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
            q
              .if_break { format_break(q, force: false) }
              .if_flat do
                Parentheses.flat(q) do
                  q.format(node.statements)
                  q.text(" #{keyword} ")
                  q.format(node.predicate)
                end
              end
          end
        end
      end
    end

    private

    def format_flat(q)
      Parentheses.flat(q) do
        q.format(node.statements.body[0])
        q.text(" #{keyword} ")
        q.format(node.predicate)
      end
    end

    def format_break(q, force:)
      q.text("#{keyword} ")
      q.nest(keyword.length + 1) { q.format(node.predicate) }

      unless node.statements.empty?
        q.indent do
          force ? q.breakable_force : q.breakable_space
          q.format(node.statements)
        end
      end

      if node.consequent
        force ? q.breakable_force : q.breakable_space
        q.format(node.consequent)
      end

      force ? q.breakable_force : q.breakable_space
      q.text("end")
    end

    def format_ternary(q)
      q.group do
        q
          .if_break do
            q.text("#{keyword} ")
            q.nest(keyword.length + 1) { q.format(node.predicate) }

            q.indent do
              q.breakable_space
              q.format(node.statements)
            end

            q.breakable_space
            q.group do
              q.format(node.consequent.keyword)
              q.indent do
                # This is a very special case of breakable where we want to
                # force it into the output but we _don't_ want to explicitly
                # break the parent. If a break-parent shows up in the tree, then
                # it's going to force it all the way up to the tree, which is
                # going to negate the ternary.
                q.breakable(force: :skip_break_parent)
                q.format(node.consequent.statements)
              end
            end

            q.breakable_space
            q.text("end")
          end
          .if_flat do
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
      statements = node.statements.body
      return false if statements.length != 1

      case statements.first
      when IfNode, IfOp, UnlessNode
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
  class IfNode < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Elsif | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_if(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    def copy(predicate: nil, statements: nil, consequent: nil, location: nil)
      node =
        IfNode.new(
          predicate: predicate || self.predicate,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(IfNode) && predicate === other.predicate &&
        statements === other.statements && consequent === other.consequent
    end

    # Checks if the node was originally found in the modifier form.
    def modifier?
      predicate.location.start_char > statements.location.start_char
    end
  end

  # IfOp represents a ternary clause.
  #
  #     predicate ? truthy : falsy
  #
  class IfOp < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Node] the expression to be executed if the predicate is truthy
    attr_reader :truthy

    # [Node] the expression to be executed if the predicate is falsy
    attr_reader :falsy

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, truthy:, falsy:, location:)
      @predicate = predicate
      @truthy = truthy
      @falsy = falsy
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_if_op(self)
    end

    def child_nodes
      [predicate, truthy, falsy]
    end

    def copy(predicate: nil, truthy: nil, falsy: nil, location: nil)
      node =
        IfOp.new(
          predicate: predicate || self.predicate,
          truthy: truthy || self.truthy,
          falsy: falsy || self.falsy,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
        AliasNode,
        Assign,
        Break,
        Command,
        CommandCall,
        Heredoc,
        IfNode,
        IfOp,
        Lambda,
        MAssign,
        Next,
        OpAssign,
        RescueMod,
        ReturnNode,
        Super,
        Undef,
        UnlessNode,
        VoidStmt,
        YieldNode,
        ZSuper
      ]

      if q.parent.is_a?(Paren) || force_flat.include?(truthy.class) ||
           force_flat.include?(falsy.class)
        q.group { format_flat(q) }
        return
      end

      q.group { q.if_break { format_break(q) }.if_flat { format_flat(q) } }
    end

    def ===(other)
      other.is_a?(IfOp) && predicate === other.predicate &&
        truthy === other.truthy && falsy === other.falsy
    end

    private

    def format_break(q)
      Parentheses.break(q) do
        q.text("if ")
        q.nest("if ".length) { q.format(predicate) }

        q.indent do
          q.breakable_space
          q.format(truthy)
        end

        q.breakable_space
        q.text("else")

        q.indent do
          q.breakable_space
          q.format(falsy)
        end

        q.breakable_space
        q.text("end")
      end
    end

    def format_flat(q)
      q.format(predicate)
      q.text(" ?")

      q.indent do
        q.breakable_space
        q.format(truthy)
        q.text(" :")

        q.breakable_space
        q.format(falsy)
      end
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_imaginary(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Imaginary.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Imaginary) && value === other.value
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
    # [Node] the pattern to check against
    attr_reader :pattern

    # [Statements] the expressions to execute if the pattern matched
    attr_reader :statements

    # [nil | In | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(pattern:, statements:, consequent:, location:)
      @pattern = pattern
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_in(self)
    end

    def child_nodes
      [pattern, statements, consequent]
    end

    def copy(pattern: nil, statements: nil, consequent: nil, location: nil)
      node =
        In.new(
          pattern: pattern || self.pattern,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      pattern = self.pattern
      consequent = self.consequent

      q.group do
        q.text(keyword)
        q.nest(keyword.length) { q.format(pattern) }
        q.text(" then") if pattern.is_a?(RangeNode) && pattern.right.nil?

        unless statements.empty?
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

    def ===(other)
      other.is_a?(In) && pattern === other.pattern &&
        statements === other.statements && consequent === other.consequent
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_int(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Int.new(value: value || self.value, location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      if !value.start_with?(/\+?0/) && value.length >= 5 && !value.include?("_")
        # If it's a plain integer and it doesn't have any underscores separating
        # the values, then we're going to insert them every 3 characters
        # starting from the right.
        index = (value.length + 2) % 3
        q.text("  #{value}"[index..].scan(/.../).join("_").strip)
      else
        q.text(value)
      end
    end

    def ===(other)
      other.is_a?(Int) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_ivar(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        IVar.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(IVar) && value === other.value
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

    # [Symbol] the symbol version of the value
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @name = value.to_sym
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_kw(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Kw.new(value: value || self.value, location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Kw) && value === other.value
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

    def initialize(name:, location:)
      @name = name
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_kwrest_param(self)
    end

    def child_nodes
      [name]
    end

    def copy(name: nil, location: nil)
      node =
        KwRestParam.new(
          name: name || self.name,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("**")
      q.format(name) if name
    end

    def ===(other)
      other.is_a?(KwRestParam) && name === other.name
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_label(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Label.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Label) && value === other.value
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

    def copy(value: nil, location: nil)
      LabelEnd.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(LabelEnd) && value === other.value
    end
  end

  # Lambda represents using a lambda literal (not the lambda method call).
  #
  #     ->(value) { value * 2 }
  #
  class Lambda < Node
    # [LambdaVar | Paren] the parameter declaration for this lambda
    attr_reader :params

    # [BodyStmt | Statements] the expressions to be executed in this lambda
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(params:, statements:, location:)
      @params = params
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_lambda(self)
    end

    def child_nodes
      [params, statements]
    end

    def copy(params: nil, statements: nil, location: nil)
      node =
        Lambda.new(
          params: params || self.params,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        params: params,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      params = self.params

      q.text("->")
      q.group do
        if params.is_a?(Paren)
          q.format(params) unless params.contents.empty?
        elsif params.empty? && params.comments.any?
          q.format(params)
        elsif !params.empty?
          q.group do
            q.text("(")
            q.format(params)
            q.text(")")
          end
        end

        q.text(" ")
        q
          .if_break do
            q.text("do")

            unless statements.empty?
              q.indent do
                q.breakable_space
                q.format(statements)
              end
            end

            q.breakable_space
            q.text("end")
          end
          .if_flat do
            q.text("{")

            unless statements.empty?
              q.text(" ")
              q.format(statements)
              q.text(" ")
            end

            q.text("}")
          end
      end
    end

    def ===(other)
      other.is_a?(Lambda) && params === other.params &&
        statements === other.statements
    end
  end

  # LambdaVar represents the parameters being declared for a lambda. Effectively
  # this node is everything contained within the parentheses. This includes all
  # of the various parameter types, as well as block-local variable
  # declarations.
  #
  #     -> (positional, optional = value, keyword:, &block; local) do
  #     end
  #
  class LambdaVar < Node
    # [Params] the parameters being declared with the block
    attr_reader :params

    # [Array[ Ident ]] the list of block-local variable declarations
    attr_reader :locals

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(params:, locals:, location:)
      @params = params
      @locals = locals
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_lambda_var(self)
    end

    def child_nodes
      [params, *locals]
    end

    def copy(params: nil, locals: nil, location: nil)
      node =
        LambdaVar.new(
          params: params || self.params,
          locals: locals || self.locals,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { params: params, locals: locals, location: location, comments: comments }
    end

    def empty?
      params.empty? && locals.empty?
    end

    def format(q)
      q.format(params)

      if locals.any?
        q.text("; ")
        q.seplist(locals, BlockVar::SEPARATOR) { |local| q.format(local) }
      end
    end

    def ===(other)
      other.is_a?(LambdaVar) && params === other.params &&
        ArrayMatch.call(locals, other.locals)
    end
  end

  # LBrace represents the use of a left brace, i.e., {.
  class LBrace < Node
    # [String] the left brace
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_lbrace(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        LBrace.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(LBrace) && value === other.value
    end

    # Because some nodes keep around a { token so that comments can be attached
    # to it if they occur in the source, oftentimes an LBrace is a child of
    # another node. This means it's required at initialization time. To make it
    # easier to create LBrace nodes without any specific value, this method
    # provides a default node.
    def self.default
      new(value: "{", location: Location.default)
    end
  end

  # LBracket represents the use of a left bracket, i.e., [.
  class LBracket < Node
    # [String] the left bracket
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_lbracket(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        LBracket.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(LBracket) && value === other.value
    end

    # Because some nodes keep around a [ token so that comments can be attached
    # to it if they occur in the source, oftentimes an LBracket is a child of
    # another node. This means it's required at initialization time. To make it
    # easier to create LBracket nodes without any specific value, this method
    # provides a default node.
    def self.default
      new(value: "[", location: Location.default)
    end
  end

  # LParen represents the use of a left parenthesis, i.e., (.
  class LParen < Node
    # [String] the left parenthesis
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_lparen(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        LParen.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(LParen) && value === other.value
    end

    # Because some nodes keep around a ( token so that comments can be attached
    # to it if they occur in the source, oftentimes an LParen is a child of
    # another node. This means it's required at initialization time. To make it
    # easier to create LParen nodes without any specific value, this method
    # provides a default node.
    def self.default
      new(value: "(", location: Location.default)
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

    # [Node] the value being assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, value:, location:)
      @target = target
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_massign(self)
    end

    def child_nodes
      [target, value]
    end

    def copy(target: nil, value: nil, location: nil)
      node =
        MAssign.new(
          target: target || self.target,
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { target: target, value: value, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.group { q.format(target) }
        q.text(" =")
        q.indent do
          q.breakable_space
          q.format(value)
        end
      end
    end

    def ===(other)
      other.is_a?(MAssign) && target === other.target && value === other.value
    end
  end

  # MethodAddBlock represents a method call with a block argument.
  #
  #     method {}
  #
  class MethodAddBlock < Node
    # [ARef | CallNode | Command | CommandCall | Super | ZSuper] the method call
    attr_reader :call

    # [BlockNode] the block being sent with the method call
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(call:, block:, location:)
      @call = call
      @block = block
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_method_add_block(self)
    end

    def child_nodes
      [call, block]
    end

    def copy(call: nil, block: nil, location: nil)
      node =
        MethodAddBlock.new(
          call: call || self.call,
          block: block || self.block,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { call: call, block: block, location: location, comments: comments }
    end

    def format(q)
      # If we're at the top of a call chain, then we're going to do some
      # specialized printing in case we can print it nicely. We _only_ do this
      # at the top of the chain to avoid weird recursion issues.
      if CallChainFormatter.chained?(call) &&
           !CallChainFormatter.chained?(q.parent)
        q.group do
          q
            .if_break { CallChainFormatter.new(self).format(q) }
            .if_flat { format_contents(q) }
        end
      else
        format_contents(q)
      end
    end

    def ===(other)
      other.is_a?(MethodAddBlock) && call === other.call &&
        block === other.block
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
    # [
    #   Array[
    #     ARefField | ArgStar | ConstPathField | Field | Ident | MLHSParen |
    #       TopConstField | VarField
    #   ]
    # ] the parts of the left-hand side of a multiple assignment
    attr_reader :parts

    # [boolean] whether or not there is a trailing comma at the end of this
    # list, which impacts destructuring. It's an attr_accessor so that while
    # the syntax tree is being built it can be set by its parent node
    attr_accessor :comma

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:, comma: false)
      @parts = parts
      @comma = comma
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_mlhs(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, location: nil, comma: nil)
      node =
        MLHS.new(
          parts: parts || self.parts,
          location: location || self.location,
          comma: comma || self.comma
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location, comma: comma, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
      q.text(",") if comma
    end

    def ===(other)
      other.is_a?(MLHS) && ArrayMatch.call(parts, other.parts) &&
        comma === other.comma
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

    def initialize(contents:, location:, comma: false)
      @contents = contents
      @comma = comma
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_mlhs_paren(self)
    end

    def child_nodes
      [contents]
    end

    def copy(contents: nil, location: nil)
      node =
        MLHSParen.new(
          contents: contents || self.contents,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { contents: contents, location: location, comments: comments }
    end

    def format(q)
      parent = q.parent

      if parent.is_a?(MAssign) || parent.is_a?(MLHSParen)
        q.format(contents)
        q.text(",") if comma
      else
        q.text("(")
        q.group do
          q.indent do
            q.breakable_empty
            q.format(contents)
          end

          q.text(",") if comma
          q.breakable_empty
        end
        q.text(")")
      end
    end

    def ===(other)
      other.is_a?(MLHSParen) && contents === other.contents
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

    def initialize(constant:, bodystmt:, location:)
      @constant = constant
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_module(self)
    end

    def child_nodes
      [constant, bodystmt]
    end

    def copy(constant: nil, bodystmt: nil, location: nil)
      node =
        ModuleDeclaration.new(
          constant: constant || self.constant,
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        constant: constant,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      if bodystmt.empty?
        q.group do
          format_declaration(q)
          q.breakable_force
          q.text("end")
        end
      else
        q.group do
          format_declaration(q)

          q.indent do
            q.breakable_force
            q.format(bodystmt)
          end

          q.breakable_force
          q.text("end")
        end
      end
    end

    def ===(other)
      other.is_a?(ModuleDeclaration) && constant === other.constant &&
        bodystmt === other.bodystmt
    end

    private

    def format_declaration(q)
      q.group do
        q.text("module ")
        q.format(constant)
      end
    end
  end

  # MRHS represents the values that are being assigned on the right-hand side of
  # a multiple assignment.
  #
  #     values = first, second, third
  #
  class MRHS < Node
    # [Array[Node]] the parts that are being assigned
    attr_reader :parts

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:)
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_mrhs(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, location: nil)
      node =
        MRHS.new(
          parts: parts || self.parts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.seplist(parts) { |part| q.format(part) }
    end

    def ===(other)
      other.is_a?(MRHS) && ArrayMatch.call(parts, other.parts)
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

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_next(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        Next.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("next", self).format(q)
    end

    def ===(other)
      other.is_a?(Next) && arguments === other.arguments
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

    # [Symbol] the symbol version of the value
    attr_reader :name

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @name = value.to_sym
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_op(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Op.new(value: value || self.value, location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Op) && value === other.value
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

    # [Node] the expression to be assigned
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, operator:, value:, location:)
      @target = target
      @operator = operator
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_opassign(self)
    end

    def child_nodes
      [target, operator, value]
    end

    def copy(target: nil, operator: nil, value: nil, location: nil)
      node =
        OpAssign.new(
          target: target || self.target,
          operator: operator || self.operator,
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
            q.breakable_space
            q.format(value)
          end
        end
      end
    end

    def ===(other)
      other.is_a?(OpAssign) && target === other.target &&
        operator === other.operator && value === other.value
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
    NODES = [
      Args,
      Assign,
      Assoc,
      Binary,
      CallNode,
      Defined,
      MAssign,
      OpAssign
    ].freeze

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
        q.breakable_empty
        yield
      end
      q.breakable_empty
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
    # Formats the optional position of the parameters. This includes the label,
    # as well as the default value.
    class OptionalFormatter
      # [Ident] the name of the parameter
      attr_reader :name

      # [Node] the value of the parameter
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

    # Formats the keyword position of the parameters. This includes the label,
    # as well as an optional default value.
    class KeywordFormatter
      # [Ident] the name of the parameter
      attr_reader :name

      # [nil | Node] the value of the parameter
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

    # Formats the keyword_rest position of the parameters. This can be the **nil
    # syntax, the ... syntax, or the ** syntax.
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
        value == :nil ? q.text("**nil") : q.format(value)
      end
    end

    # [Array[ Ident | MLHSParen ]] any required parameters
    attr_reader :requireds

    # [Array[ [ Ident, Node ] ]] any optional parameters and their default
    # values
    attr_reader :optionals

    # [nil | ArgsForward | ExcessedComma | RestParam] the optional rest
    # parameter
    attr_reader :rest

    # [Array[ Ident | MLHSParen ]] any positional parameters that exist after a
    #  rest parameter
    attr_reader :posts

    # [Array[ [ Label, nil | Node ] ]] any keyword parameters and their
    # optional default values
    attr_reader :keywords

    # [nil | :nil | ArgsForward | KwRestParam] the optional keyword rest
    # parameter
    attr_reader :keyword_rest

    # [nil | BlockArg] the optional block parameter
    attr_reader :block

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(
      location:,
      requireds: [],
      optionals: [],
      rest: nil,
      posts: [],
      keywords: [],
      keyword_rest: nil,
      block: nil
    )
      @requireds = requireds
      @optionals = optionals
      @rest = rest
      @posts = posts
      @keywords = keywords
      @keyword_rest = keyword_rest
      @block = block
      @location = location
      @comments = []
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
      keyword_rest = self.keyword_rest

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

    def copy(
      location: nil,
      requireds: nil,
      optionals: nil,
      rest: nil,
      posts: nil,
      keywords: nil,
      keyword_rest: nil,
      block: nil
    )
      node =
        Params.new(
          location: location || self.location,
          requireds: requireds || self.requireds,
          optionals: optionals || self.optionals,
          rest: rest || self.rest,
          posts: posts || self.posts,
          keywords: keywords || self.keywords,
          keyword_rest: keyword_rest || self.keyword_rest,
          block: block || self.block
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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
      rest = self.rest
      keyword_rest = self.keyword_rest

      parts = [
        *requireds,
        *optionals.map { |(name, value)| OptionalFormatter.new(name, value) }
      ]

      parts << rest if rest && !rest.is_a?(ExcessedComma)
      parts.concat(posts)
      parts.concat(
        keywords.map { |(name, value)| KeywordFormatter.new(name, value) }
      )

      parts << KeywordRestFormatter.new(keyword_rest) if keyword_rest
      parts << block if block

      if parts.empty?
        q.nest(0) { format_contents(q, parts) }
        return
      end

      if q.parent.is_a?(DefNode)
        q.nest(0) do
          q.text("(")
          q.group do
            q.indent do
              q.breakable_empty
              format_contents(q, parts)
            end
            q.breakable_empty
          end
          q.text(")")
        end
      else
        q.nest(0) { format_contents(q, parts) }
      end
    end

    def ===(other)
      other.is_a?(Params) && ArrayMatch.call(requireds, other.requireds) &&
        optionals.length == other.optionals.length &&
        optionals
          .zip(other.optionals)
          .all? { |left, right| ArrayMatch.call(left, right) } &&
        rest === other.rest && ArrayMatch.call(posts, other.posts) &&
        keywords.length == other.keywords.length &&
        keywords
          .zip(other.keywords)
          .all? { |left, right| ArrayMatch.call(left, right) } &&
        keyword_rest === other.keyword_rest && block === other.block
    end

    # Returns a range representing the possible number of arguments accepted
    # by this params node not including the block. For example:
    #
    #     def foo(a, b = 1, c:, d: 2, &block)
    #       ...
    #     end
    #
    # has arity 2..4.
    #
    def arity
      optional_keywords = keywords.count { |_label, value| value }

      lower_bound =
        requireds.length + posts.length + keywords.length - optional_keywords

      upper_bound =
        if keyword_rest.nil? && rest.nil?
          lower_bound + optionals.length + optional_keywords
        end

      lower_bound..upper_bound
    end

    private

    def format_contents(q, parts)
      q.seplist(parts) { |part| q.format(part) }
      q.format(rest) if rest.is_a?(ExcessedComma)
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

    # [nil | Node] the expression inside the parentheses
    attr_reader :contents

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(lparen:, contents:, location:)
      @lparen = lparen
      @contents = contents
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_paren(self)
    end

    def child_nodes
      [lparen, contents]
    end

    def copy(lparen: nil, contents: nil, location: nil)
      node =
        Paren.new(
          lparen: lparen || self.lparen,
          contents: contents || self.contents,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        lparen: lparen,
        contents: contents,
        location: location,
        comments: comments
      }
    end

    def format(q)
      contents = self.contents

      q.group do
        q.format(lparen)

        if contents && (!contents.is_a?(Params) || !contents.empty?)
          q.indent do
            q.breakable_empty
            q.format(contents)
          end
        end

        q.breakable_empty
        q.text(")")
      end
    end

    def ===(other)
      other.is_a?(Paren) && lparen === other.lparen &&
        contents === other.contents
    end
  end

  # Period represents the use of the +.+ operator. It is usually found in method
  # calls.
  class Period < Node
    # [String] the period
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_period(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        Period.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(Period) && value === other.value
    end
  end

  # Program represents the overall syntax tree.
  class Program < Node
    # [Statements] the top-level expressions of the program
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statements:, location:)
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_program(self)
    end

    def child_nodes
      [statements]
    end

    def copy(statements: nil, location: nil)
      node =
        Program.new(
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { statements: statements, location: location, comments: comments }
    end

    def format(q)
      q.format(statements)

      # We're going to put a newline on the end so that it always has one unless
      # it ends with the special __END__ syntax. In that case we want to
      # replicate the text exactly so we will just let it be.
      q.breakable_force unless statements.body.last.is_a?(EndContent)
    end

    def ===(other)
      other.is_a?(Program) && statements === other.statements
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

    def initialize(beginning:, elements:, location:)
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_qsymbols(self)
    end

    def child_nodes
      []
    end

    def copy(beginning: nil, elements: nil, location: nil)
      node =
        QSymbols.new(
          beginning: beginning || self.beginning,
          elements: elements || self.elements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

      q.text(opening)
      q.group do
        q.indent do
          q.breakable_empty
          q.seplist(
            elements,
            ArrayLiteral::BREAKABLE_SPACE_SEPARATOR
          ) { |element| q.format(element) }
        end
        q.breakable_empty
      end
      q.text(closing)
    end

    def ===(other)
      other.is_a?(QSymbols) && beginning === other.beginning &&
        ArrayMatch.call(elements, other.elements)
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

    def copy(value: nil, location: nil)
      QSymbolsBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(QSymbolsBeg) && value === other.value
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

    def initialize(beginning:, elements:, location:)
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_qwords(self)
    end

    def child_nodes
      []
    end

    def copy(beginning: nil, elements: nil, location: nil)
      QWords.new(
        beginning: beginning || self.beginning,
        elements: elements || self.elements,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

      q.text(opening)
      q.group do
        q.indent do
          q.breakable_empty
          q.seplist(
            elements,
            ArrayLiteral::BREAKABLE_SPACE_SEPARATOR
          ) { |element| q.format(element) }
        end
        q.breakable_empty
      end
      q.text(closing)
    end

    def ===(other)
      other.is_a?(QWords) && beginning === other.beginning &&
        ArrayMatch.call(elements, other.elements)
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

    def copy(value: nil, location: nil)
      QWordsBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(QWordsBeg) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_rational(self)
    end

    def child_nodes
      []
    end

    def copy(value: nil, location: nil)
      node =
        RationalLiteral.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(RationalLiteral) && value === other.value
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

    def copy(value: nil, location: nil)
      RBrace.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(RBrace) && value === other.value
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

    def copy(value: nil, location: nil)
      RBracket.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(RBracket) && value === other.value
    end
  end

  # Redo represents the use of the +redo+ keyword.
  #
  #     redo
  #
  class Redo < Node
    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:)
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_redo(self)
    end

    def child_nodes
      []
    end

    def copy(location: nil)
      node = Redo.new(location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { location: location, comments: comments }
    end

    def format(q)
      q.text("redo")
    end

    def ===(other)
      other.is_a?(Redo)
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

    def copy(beginning: nil, parts: nil, location: nil)
      RegexpContent.new(
        beginning: beginning || self.beginning,
        parts: parts || self.parts,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { beginning: beginning, parts: parts, location: location }
    end

    def ===(other)
      other.is_a?(RegexpContent) && beginning === other.beginning &&
        parts === other.parts
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

    def copy(value: nil, location: nil)
      RegexpBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(RegexpBeg) && value === other.value
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

    def copy(value: nil, location: nil)
      RegexpEnd.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(RegexpEnd) && value === other.value
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

    def initialize(beginning:, ending:, parts:, location:)
      @beginning = beginning
      @ending = ending
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_regexp_literal(self)
    end

    def child_nodes
      parts
    end

    def copy(beginning: nil, ending: nil, parts: nil, location: nil)
      node =
        RegexpLiteral.new(
          beginning: beginning || self.beginning,
          ending: ending || self.ending,
          parts: parts || self.parts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        beginning: beginning,
        ending: ending,
        options: options,
        parts: parts,
        location: location,
        comments: comments
      }
    end

    def format(q)
      braces = ambiguous?(q) || include?(%r{/})

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
          q.text(options)
        end
      else
        q.group do
          q.text("/")
          q.format_each(parts)
          q.text("/")
          q.text(options)
        end
      end
    end

    def ===(other)
      other.is_a?(RegexpLiteral) && beginning === other.beginning &&
        ending === other.ending && options === other.options &&
        ArrayMatch.call(parts, other.parts)
    end

    def options
      ending[1..]
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
    # [nil | Node] the list of exceptions being rescued
    attr_reader :exceptions

    # [nil | Field | VarField] the expression being used to capture the raised
    # exception
    attr_reader :variable

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(exceptions:, variable:, location:)
      @exceptions = exceptions
      @variable = variable
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_rescue_ex(self)
    end

    def child_nodes
      [*exceptions, variable]
    end

    def copy(exceptions: nil, variable: nil, location: nil)
      node =
        RescueEx.new(
          exceptions: exceptions || self.exceptions,
          variable: variable || self.variable,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(RescueEx) && exceptions === other.exceptions &&
        variable === other.variable
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

    # [nil | RescueEx] the exceptions being rescued
    attr_reader :exception

    # [Statements] the expressions to evaluate when an error is rescued
    attr_reader :statements

    # [nil | Rescue] the optional next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(keyword:, exception:, statements:, consequent:, location:)
      @keyword = keyword
      @exception = exception
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
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

      if (next_node = consequent)
        next_node.bind_end(end_char, end_column)
        statements.bind_end(
          next_node.location.start_char,
          next_node.location.start_column
        )
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

    def copy(
      keyword: nil,
      exception: nil,
      statements: nil,
      consequent: nil,
      location: nil
    )
      node =
        Rescue.new(
          keyword: keyword || self.keyword,
          exception: exception || self.exception,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(Rescue) && keyword === other.keyword &&
        exception === other.exception && statements === other.statements &&
        consequent === other.consequent
    end
  end

  # RescueMod represents the use of the modifier form of a +rescue+ clause.
  #
  #     expression rescue value
  #
  class RescueMod < Node
    # [Node] the expression to execute
    attr_reader :statement

    # [Node] the value to use if the executed expression raises an error
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, value:, location:)
      @statement = statement
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_rescue_mod(self)
    end

    def child_nodes
      [statement, value]
    end

    def copy(statement: nil, value: nil, location: nil)
      node =
        RescueMod.new(
          statement: statement || self.statement,
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        statement: statement,
        value: value,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.text("begin")
      q.group do
        q.indent do
          q.breakable_force
          q.format(statement)
        end
        q.breakable_force
        q.text("rescue StandardError")
        q.indent do
          q.breakable_force
          q.format(value)
        end
        q.breakable_force
      end
      q.text("end")
    end

    def ===(other)
      other.is_a?(RescueMod) && statement === other.statement &&
        value === other.value
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

    def initialize(name:, location:)
      @name = name
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_rest_param(self)
    end

    def child_nodes
      [name]
    end

    def copy(name: nil, location: nil)
      node =
        RestParam.new(
          name: name || self.name,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { name: name, location: location, comments: comments }
    end

    def format(q)
      q.text("*")
      q.format(name) if name
    end

    def ===(other)
      other.is_a?(RestParam) && name === other.name
    end
  end

  # Retry represents the use of the +retry+ keyword.
  #
  #     retry
  #
  class Retry < Node
    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:)
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_retry(self)
    end

    def child_nodes
      []
    end

    def copy(location: nil)
      node = Retry.new(location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { location: location, comments: comments }
    end

    def format(q)
      q.text("retry")
    end

    def ===(other)
      other.is_a?(Retry)
    end
  end

  # Return represents using the +return+ keyword with arguments.
  #
  #     return value
  #
  class ReturnNode < Node
    # [nil | Args] the arguments being passed to the keyword
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_return(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        ReturnNode.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      FlowControlFormatter.new("return", self).format(q)
    end

    def ===(other)
      other.is_a?(ReturnNode) && arguments === other.arguments
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

    def copy(value: nil, location: nil)
      RParen.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(RParen) && value === other.value
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
    # [Node] the target of the singleton class to enter
    attr_reader :target

    # [BodyStmt] the expressions to be executed
    attr_reader :bodystmt

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(target:, bodystmt:, location:)
      @target = target
      @bodystmt = bodystmt
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_sclass(self)
    end

    def child_nodes
      [target, bodystmt]
    end

    def copy(target: nil, bodystmt: nil, location: nil)
      node =
        SClass.new(
          target: target || self.target,
          bodystmt: bodystmt || self.bodystmt,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        target: target,
        bodystmt: bodystmt,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.text("class << ")
      q.group do
        q.format(target)
        q.indent do
          q.breakable_force
          q.format(bodystmt)
        end
        q.breakable_force
      end
      q.text("end")
    end

    def ===(other)
      other.is_a?(SClass) && target === other.target &&
        bodystmt === other.bodystmt
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
    # [Array[ Node ]] the list of expressions contained within this node
    attr_reader :body

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(body:, location:)
      @body = body
      @location = location
      @comments = []
    end

    def bind(parser, start_char, start_column, end_char, end_column)
      @location =
        Location.new(
          start_line: location.start_line,
          start_char: start_char,
          start_column: start_column,
          end_line: location.end_line,
          end_char: end_char,
          end_column: end_column
        )

      if (void_stmt = body[0]).is_a?(VoidStmt)
        location = void_stmt.location
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

      attach_comments(parser, start_char, end_char)
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

    def copy(body: nil, location: nil)
      node =
        Statements.new(
          body: body || self.body,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { body: body, location: location, comments: comments }
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

      previous = nil
      body.each do |statement|
        next if statement.is_a?(VoidStmt)

        if line.nil?
          q.format(statement)
        elsif (statement.location.start_line - line) > 1
          q.breakable_force
          q.breakable_force
          q.format(statement)
        elsif (statement.is_a?(VCall) && statement.access_control?) ||
              (previous.is_a?(VCall) && previous.access_control?)
          q.breakable_force
          q.breakable_force
          q.format(statement)
        elsif statement.location.start_line != line
          q.breakable_force
          q.format(statement)
        elsif !q.parent.is_a?(StringEmbExpr)
          q.breakable_force
          q.format(statement)
        else
          q.text("; ")
          q.format(statement)
        end

        line = statement.location.end_line
        previous = statement
      end
    end

    def ===(other)
      other.is_a?(Statements) && ArrayMatch.call(body, other.body)
    end

    private

    # As efficiently as possible, gather up all of the comments that have been
    # found while this statements list was being parsed and add them into the
    # body.
    def attach_comments(parser, start_char, end_char)
      parser_comments = parser.comments

      comment_index = 0
      body_index = 0

      while comment_index < parser_comments.size
        comment = parser_comments[comment_index]
        location = comment.location

        if !comment.inline? && (start_char <= location.start_char) &&
             (end_char >= location.end_char) && !comment.ignore?
          while (node = body[body_index]) &&
                  (
                    node.is_a?(VoidStmt) ||
                      node.location.start_char < location.start_char
                  )
            body_index += 1
          end

          if body_index != 0 &&
               body[body_index - 1].location.start_char < location.start_char &&
               body[body_index - 1].location.end_char > location.start_char
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

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, location:)
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_string_content(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, location: nil)
      StringContent.new(
        parts: parts || self.parts,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location }
    end

    def ===(other)
      other.is_a?(StringContent) && ArrayMatch.call(parts, other.parts)
    end

    def format(q)
      q.text(q.quote)
      q.group do
        parts.each do |part|
          if part.is_a?(TStringContent)
            value = Quotes.normalize(part.value, q.quote)
            first = true

            value.each_line(chomp: true) do |line|
              if first
                first = false
              else
                q.breakable_return
              end

              q.text(line)
            end

            q.breakable_return if value.end_with?("\n")
          else
            q.format(part)
          end
        end
      end
      q.text(q.quote)
    end
  end

  # StringConcat represents concatenating two strings together using a backward
  # slash.
  #
  #     "first" \
  #       "second"
  #
  class StringConcat < Node
    # [Heredoc | StringConcat | StringLiteral] the left side of the
    # concatenation
    attr_reader :left

    # [StringLiteral] the right side of the concatenation
    attr_reader :right

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(left:, right:, location:)
      @left = left
      @right = right
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_string_concat(self)
    end

    def child_nodes
      [left, right]
    end

    def copy(left: nil, right: nil, location: nil)
      node =
        StringConcat.new(
          left: left || self.left,
          right: right || self.right,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { left: left, right: right, location: location, comments: comments }
    end

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

    def ===(other)
      other.is_a?(StringConcat) && left === other.left && right === other.right
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

    def initialize(variable:, location:)
      @variable = variable
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_string_dvar(self)
    end

    def child_nodes
      [variable]
    end

    def copy(variable: nil, location: nil)
      node =
        StringDVar.new(
          variable: variable || self.variable,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { variable: variable, location: location, comments: comments }
    end

    def format(q)
      q.text('#{')
      q.format(variable)
      q.text("}")
    end

    def ===(other)
      other.is_a?(StringDVar) && variable === other.variable
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

    def initialize(statements:, location:)
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_string_embexpr(self)
    end

    def child_nodes
      [statements]
    end

    def copy(statements: nil, location: nil)
      node =
        StringEmbExpr.new(
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { statements: statements, location: location, comments: comments }
    end

    def format(q)
      if location.start_line == location.end_line
        # If the contents of this embedded expression were originally on the
        # same line in the source, then we're going to leave them in place and
        # assume that's the way the developer wanted this expression
        # represented.
        q.remove_breaks(
          q.group do
            q.text('#{')
            q.format(statements)
            q.text("}")
          end
        )
      else
        q.group do
          q.text('#{')
          q.indent do
            q.breakable_empty
            q.format(statements)
          end
          q.breakable_empty
          q.text("}")
        end
      end
    end

    def ===(other)
      other.is_a?(StringEmbExpr) && statements === other.statements
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

    # [nil | String] which quote was used by the string literal
    attr_reader :quote

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(parts:, quote:, location:)
      @parts = parts
      @quote = quote
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_string_literal(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, quote: nil, location: nil)
      node =
        StringLiteral.new(
          parts: parts || self.parts,
          quote: quote || self.quote,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, quote: quote, location: location, comments: comments }
    end

    def format(q)
      if parts.empty?
        q.text("#{q.quote}#{q.quote}")
        return
      end

      opening_quote, closing_quote =
        if !Quotes.locked?(self, q.quote)
          [q.quote, q.quote]
        elsif quote&.start_with?("%")
          [quote, Quotes.matching(quote[/%[qQ]?(.)/, 1])]
        else
          [quote, quote]
        end

      q.text(opening_quote)
      q.group do
        parts.each do |part|
          if part.is_a?(TStringContent)
            value = Quotes.normalize(part.value, closing_quote)
            first = true

            value.each_line(chomp: true) do |line|
              if first
                first = false
              else
                q.breakable_return
              end

              q.text(line)
            end

            q.breakable_return if value.end_with?("\n")
          else
            q.format(part)
          end
        end
      end
      q.text(closing_quote)
    end

    def ===(other)
      other.is_a?(StringLiteral) && ArrayMatch.call(parts, other.parts) &&
        quote === other.quote
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

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_super(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        Super.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(Super) && arguments === other.arguments
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

    def copy(value: nil, location: nil)
      SymBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(SymBeg) && value === other.value
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

    def copy(value: nil, location: nil)
      SymbolContent.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(SymbolContent) && value === other.value
    end
  end

  # SymbolLiteral represents a symbol in the system with no interpolation
  # (as opposed to a DynaSymbol which has interpolation).
  #
  #     :symbol
  #
  class SymbolLiteral < Node
    # [Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op | TStringContent]
    # the value of the symbol
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_symbol_literal(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        SymbolLiteral.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(":")
      q.text("\\") if value.comments.any?
      q.format(value)
    end

    def ===(other)
      other.is_a?(SymbolLiteral) && value === other.value
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

    def initialize(beginning:, elements:, location:)
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_symbols(self)
    end

    def child_nodes
      []
    end

    def copy(beginning: nil, elements: nil, location: nil)
      Symbols.new(
        beginning: beginning || self.beginning,
        elements: elements || self.elements,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

      q.text(opening)
      q.group do
        q.indent do
          q.breakable_empty
          q.seplist(
            elements,
            ArrayLiteral::BREAKABLE_SPACE_SEPARATOR
          ) { |element| q.format(element) }
        end
        q.breakable_empty
      end
      q.text(closing)
    end

    def ===(other)
      other.is_a?(Symbols) && beginning === other.beginning &&
        ArrayMatch.call(elements, other.elements)
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

    def copy(value: nil, location: nil)
      SymbolsBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(SymbolsBeg) && value === other.value
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

    def copy(value: nil, location: nil)
      TLambda.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(TLambda) && value === other.value
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

    def copy(value: nil, location: nil)
      TLamBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(TLamBeg) && value === other.value
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

    def initialize(constant:, location:)
      @constant = constant
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_top_const_field(self)
    end

    def child_nodes
      [constant]
    end

    def copy(constant: nil, location: nil)
      node =
        TopConstField.new(
          constant: constant || self.constant,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.text("::")
      q.format(constant)
    end

    def ===(other)
      other.is_a?(TopConstField) && constant === other.constant
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

    def initialize(constant:, location:)
      @constant = constant
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_top_const_ref(self)
    end

    def child_nodes
      [constant]
    end

    def copy(constant: nil, location: nil)
      node =
        TopConstRef.new(
          constant: constant || self.constant,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { constant: constant, location: location, comments: comments }
    end

    def format(q)
      q.text("::")
      q.format(constant)
    end

    def ===(other)
      other.is_a?(TopConstRef) && constant === other.constant
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

    def copy(value: nil, location: nil)
      TStringBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(TStringBeg) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
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

    def copy(value: nil, location: nil)
      node =
        TStringContent.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.text(value)
    end

    def ===(other)
      other.is_a?(TStringContent) && value === other.value
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

    def copy(value: nil, location: nil)
      TStringEnd.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(TStringEnd) && value === other.value
    end
  end

  # Not represents the unary +not+ method being called on an expression.
  #
  #     not value
  #
  class Not < Node
    # [nil | Node] the statement on which to operate
    attr_reader :statement

    # [boolean] whether or not parentheses were used
    attr_reader :parentheses
    alias parentheses? parentheses

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(statement:, parentheses:, location:)
      @statement = statement
      @parentheses = parentheses
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_not(self)
    end

    def child_nodes
      [statement]
    end

    def copy(statement: nil, parentheses: nil, location: nil)
      node =
        Not.new(
          statement: statement || self.statement,
          parentheses: parentheses || self.parentheses,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        statement: statement,
        parentheses: parentheses,
        location: location,
        comments: comments
      }
    end

    def format(q)
      q.text("not")

      if parentheses
        q.text("(")
        q.format(statement) if statement
        q.text(")")
      else
        grandparent = q.grandparent
        ternary =
          (grandparent.is_a?(IfNode) || grandparent.is_a?(UnlessNode)) &&
            Ternaryable.call(q, grandparent)

        if ternary
          q.if_break { q.text(" ") }.if_flat { q.text("(") }
          q.format(statement) if statement
          q.if_flat { q.text(")") } if ternary
        else
          q.text(" ")
          q.format(statement) if statement
        end
      end
    end

    def ===(other)
      other.is_a?(Not) && statement === other.statement &&
        parentheses === other.parentheses
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

    # [Node] the statement on which to operate
    attr_reader :statement

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(operator:, statement:, location:)
      @operator = operator
      @statement = statement
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_unary(self)
    end

    def child_nodes
      [statement]
    end

    def copy(operator: nil, statement: nil, location: nil)
      node =
        Unary.new(
          operator: operator || self.operator,
          statement: statement || self.statement,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(Unary) && operator === other.operator &&
        statement === other.statement
    end
  end

  # Undef represents the use of the +undef+ keyword.
  #
  #     undef method
  #
  class Undef < Node
    # Undef accepts a variable number of arguments that can be either DynaSymbol
    # or SymbolLiteral objects. For SymbolLiteral objects we descend directly
    # into the value in order to have it come out as bare words.
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

    def initialize(symbols:, location:)
      @symbols = symbols
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_undef(self)
    end

    def child_nodes
      symbols
    end

    def copy(symbols: nil, location: nil)
      node =
        Undef.new(
          symbols: symbols || self.symbols,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(Undef) && ArrayMatch.call(symbols, other.symbols)
    end
  end

  # Unless represents the first clause in an +unless+ chain.
  #
  #     unless predicate
  #     end
  #
  class UnlessNode < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [nil | Elsif | Else] the next clause in the chain
    attr_reader :consequent

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, consequent:, location:)
      @predicate = predicate
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_unless(self)
    end

    def child_nodes
      [predicate, statements, consequent]
    end

    def copy(predicate: nil, statements: nil, consequent: nil, location: nil)
      node =
        UnlessNode.new(
          predicate: predicate || self.predicate,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

    def ===(other)
      other.is_a?(UnlessNode) && predicate === other.predicate &&
        statements === other.statements && consequent === other.consequent
    end

    # Checks if the node was originally found in the modifier form.
    def modifier?
      predicate.location.start_char > statements.location.start_char
    end
  end

  # Formats an Until or While node.
  class LoopFormatter
    # [String] the name of the keyword used for this loop
    attr_reader :keyword

    # [Until | While] the node that is being formatted
    attr_reader :node

    def initialize(keyword, node)
      @keyword = keyword
      @node = node
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
      if node.modifier? && (statement = node.statements.body.first) &&
           (statement.is_a?(Begin) || ContainsAssignment.call(statement))
        q.format(statement)
        q.text(" #{keyword} ")
        q.format(node.predicate)
      elsif node.statements.empty?
        q.group do
          q.text("#{keyword} ")
          q.nest(keyword.length + 1) { q.format(node.predicate) }
          q.breakable_force
          q.text("end")
        end
      elsif ContainsAssignment.call(node.predicate)
        format_break(q)
        q.break_parent
      else
        q.group do
          q
            .if_break { format_break(q) }
            .if_flat do
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

    def format_break(q)
      q.text("#{keyword} ")
      q.nest(keyword.length + 1) { q.format(node.predicate) }
      q.indent do
        q.breakable_empty
        q.format(node.statements)
      end
      q.breakable_empty
      q.text("end")
    end
  end

  # Until represents an +until+ loop.
  #
  #     until predicate
  #     end
  #
  class UntilNode < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, location:)
      @predicate = predicate
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_until(self)
    end

    def child_nodes
      [predicate, statements]
    end

    def copy(predicate: nil, statements: nil, location: nil)
      node =
        UntilNode.new(
          predicate: predicate || self.predicate,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        predicate: predicate,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      LoopFormatter.new("until", self).format(q)
    end

    def ===(other)
      other.is_a?(UntilNode) && predicate === other.predicate &&
        statements === other.statements
    end

    def modifier?
      predicate.location.start_char > statements.location.start_char
    end
  end

  # VarField represents a variable that is being assigned a value. As such, it
  # is always a child of an assignment type node.
  #
  #     variable = value
  #
  # In the example above, the VarField node represents the +variable+ token.
  class VarField < Node
    # [nil | :nil | Const | CVar | GVar | Ident | IVar] the target of this node
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_var_field(self)
    end

    def child_nodes
      value == :nil ? [] : [value]
    end

    def copy(value: nil, location: nil)
      node =
        VarField.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      if value == :nil
        q.text("nil")
      elsif value
        q.format(value)
      end
    end

    def ===(other)
      other.is_a?(VarField) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_var_ref(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        VarRef.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.format(value)
    end

    def ===(other)
      other.is_a?(VarRef) && value === other.value
    end

    # Oh man I hate this so much. Basically, ripper doesn't provide enough
    # functionality to actually know where pins are within an expression. So we
    # have to walk the tree ourselves and insert more information. In doing so,
    # we have to replace this node by a pinned node when necessary.
    #
    # To be clear, this method should just not exist. It's not good. It's a
    # place of shame. But it's necessary for now, so I'm keeping it.
    def pin(parent, pin)
      replace =
        PinnedVarRef.new(value: value, location: pin.location.to(location))

      parent
        .deconstruct_keys([])
        .each do |key, value|
          if value == self
            parent.instance_variable_set(:"@#{key}", replace)
            break
          elsif value.is_a?(Array) && (index = value.index(self))
            parent.public_send(key)[index] = replace
            break
          end
        end
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
    # [Const | CVar | GVar | Ident | IVar] the value of this node
    attr_reader :value

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_pinned_var_ref(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        PinnedVarRef.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.group do
        q.text("^")
        q.format(value)
      end
    end

    def ===(other)
      other.is_a?(PinnedVarRef) && value === other.value
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

    def initialize(value:, location:)
      @value = value
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_vcall(self)
    end

    def child_nodes
      [value]
    end

    def copy(value: nil, location: nil)
      node =
        VCall.new(
          value: value || self.value,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location, comments: comments }
    end

    def format(q)
      q.format(value)
    end

    def ===(other)
      other.is_a?(VCall) && value === other.value
    end

    def access_control?
      @access_control ||= %w[private protected public].include?(value.value)
    end

    def arity
      0
    end
  end

  # VoidStmt represents an empty lexical block of code.
  #
  #     ;;
  #
  class VoidStmt < Node
    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:)
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_void_stmt(self)
    end

    def child_nodes
      []
    end

    def copy(location: nil)
      node = VoidStmt.new(location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { location: location, comments: comments }
    end

    def format(q)
    end

    def ===(other)
      other.is_a?(VoidStmt)
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

    def initialize(arguments:, statements:, consequent:, location:)
      @arguments = arguments
      @statements = statements
      @consequent = consequent
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_when(self)
    end

    def child_nodes
      [arguments, statements, consequent]
    end

    def copy(arguments: nil, statements: nil, consequent: nil, location: nil)
      node =
        When.new(
          arguments: arguments || self.arguments,
          statements: statements || self.statements,
          consequent: consequent || self.consequent,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        arguments: arguments,
        statements: statements,
        consequent: consequent,
        location: location,
        comments: comments
      }
    end

    # We have a special separator here for when clauses which causes them to
    # fill as much of the line as possible as opposed to everything breaking
    # into its own line as soon as you hit the print limit.
    class Separator
      def call(q)
        q.group do
          q.text(",")
          q.breakable_space
        end
      end
    end

    # We're going to keep a single instance of this separator around so we don't
    # have to allocate a new one every time we format a when clause.
    SEPARATOR = Separator.new.freeze

    def format(q)
      keyword = "when "

      q.group do
        q.group do
          q.text(keyword)
          q.nest(keyword.length) do
            if arguments.comments.any?
              q.format(arguments)
            else
              q.seplist(arguments.parts, SEPARATOR) { |part| q.format(part) }
            end

            # Very special case here. If you're inside of a when clause and the
            # last argument to the predicate is and endless range, then you are
            # forced to use the "then" keyword to make it parse properly.
            last = arguments.parts.last
            q.text(" then") if last.is_a?(RangeNode) && !last.right
          end
        end

        unless statements.empty?
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

    def ===(other)
      other.is_a?(When) && arguments === other.arguments &&
        statements === other.statements && consequent === other.consequent
    end
  end

  # While represents a +while+ loop.
  #
  #     while predicate
  #     end
  #
  class WhileNode < Node
    # [Node] the expression to be checked
    attr_reader :predicate

    # [Statements] the expressions to be executed
    attr_reader :statements

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(predicate:, statements:, location:)
      @predicate = predicate
      @statements = statements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_while(self)
    end

    def child_nodes
      [predicate, statements]
    end

    def copy(predicate: nil, statements: nil, location: nil)
      node =
        WhileNode.new(
          predicate: predicate || self.predicate,
          statements: statements || self.statements,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      {
        predicate: predicate,
        statements: statements,
        location: location,
        comments: comments
      }
    end

    def format(q)
      LoopFormatter.new("while", self).format(q)
    end

    def ===(other)
      other.is_a?(WhileNode) && predicate === other.predicate &&
        statements === other.statements
    end

    def modifier?
      predicate.location.start_char > statements.location.start_char
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

    def initialize(parts:, location:)
      @parts = parts
      @location = location
      @comments = []
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

    def copy(parts: nil, location: nil)
      node =
        Word.new(
          parts: parts || self.parts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.format_each(parts)
    end

    def ===(other)
      other.is_a?(Word) && ArrayMatch.call(parts, other.parts)
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

    def initialize(beginning:, elements:, location:)
      @beginning = beginning
      @elements = elements
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_words(self)
    end

    def child_nodes
      []
    end

    def copy(beginning: nil, elements: nil, location: nil)
      Words.new(
        beginning: beginning || self.beginning,
        elements: elements || self.elements,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
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

      q.text(opening)
      q.group do
        q.indent do
          q.breakable_empty
          q.seplist(
            elements,
            ArrayLiteral::BREAKABLE_SPACE_SEPARATOR
          ) { |element| q.format(element) }
        end
        q.breakable_empty
      end
      q.text(closing)
    end

    def ===(other)
      other.is_a?(Words) && beginning === other.beginning &&
        ArrayMatch.call(elements, other.elements)
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

    def copy(value: nil, location: nil)
      WordsBeg.new(
        value: value || self.value,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { value: value, location: location }
    end

    def ===(other)
      other.is_a?(WordsBeg) && value === other.value
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

    def copy(parts: nil, location: nil)
      XString.new(
        parts: parts || self.parts,
        location: location || self.location
      )
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location }
    end

    def ===(other)
      other.is_a?(XString) && ArrayMatch.call(parts, other.parts)
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

    def initialize(parts:, location:)
      @parts = parts
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_xstring_literal(self)
    end

    def child_nodes
      parts
    end

    def copy(parts: nil, location: nil)
      node =
        XStringLiteral.new(
          parts: parts || self.parts,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { parts: parts, location: location, comments: comments }
    end

    def format(q)
      q.text("`")
      q.format_each(parts)
      q.text("`")
    end

    def ===(other)
      other.is_a?(XStringLiteral) && ArrayMatch.call(parts, other.parts)
    end
  end

  # Yield represents using the +yield+ keyword with arguments.
  #
  #     yield value
  #
  class YieldNode < Node
    # [nil | Args | Paren] the arguments passed to the yield
    attr_reader :arguments

    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(arguments:, location:)
      @arguments = arguments
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_yield(self)
    end

    def child_nodes
      [arguments]
    end

    def copy(arguments: nil, location: nil)
      node =
        YieldNode.new(
          arguments: arguments || self.arguments,
          location: location || self.location
        )

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { arguments: arguments, location: location, comments: comments }
    end

    def format(q)
      if arguments.nil?
        q.text("yield")
        return
      end

      q.group do
        q.text("yield")

        if arguments.is_a?(Paren)
          q.format(arguments)
        else
          q.if_break { q.text("(") }.if_flat { q.text(" ") }
          q.indent do
            q.breakable_empty
            q.format(arguments)
          end
          q.breakable_empty
          q.if_break { q.text(")") }
        end
      end
    end

    def ===(other)
      other.is_a?(YieldNode) && arguments === other.arguments
    end
  end

  # ZSuper represents the bare +super+ keyword with no arguments.
  #
  #     super
  #
  class ZSuper < Node
    # [Array[ Comment | EmbDoc ]] the comments attached to this node
    attr_reader :comments

    def initialize(location:)
      @location = location
      @comments = []
    end

    def accept(visitor)
      visitor.visit_zsuper(self)
    end

    def child_nodes
      []
    end

    def copy(location: nil)
      node = ZSuper.new(location: location || self.location)

      node.comments.concat(comments.map(&:copy))
      node
    end

    alias deconstruct child_nodes

    def deconstruct_keys(_keys)
      { location: location, comments: comments }
    end

    def format(q)
      q.text("super")
    end

    def ===(other)
      other.is_a?(ZSuper)
    end
  end
end
