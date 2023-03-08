# frozen_string_literal: true

module SyntaxTree
  # Parser is a subclass of the Ripper library that subscribes to the stream of
  # tokens and nodes coming from the parser and builds up a syntax tree.
  class Parser < Ripper
    # A special parser error so that we can get nice syntax displays on the
    # error message when prettier prints out the results.
    class ParseError < StandardError
      attr_reader :lineno, :column

      def initialize(error, lineno, column)
        super(error)
        @lineno = lineno
        @column = column
      end
    end

    # Represents a line in the source. If this class is being used, it means
    # that every character in the string is 1 byte in length, so we can just
    # return the start of the line + the index.
    class SingleByteString
      attr_reader :start

      def initialize(start)
        @start = start
      end

      def [](byteindex)
        start + byteindex
      end
    end

    # Represents a line in the source. If this class is being used, it means
    # that there are characters in the string that are multi-byte, so we will
    # build up an array of indices, such that array[byteindex] will be equal to
    # the index of the character within the string.
    class MultiByteString
      attr_reader :start, :indices

      def initialize(start, line)
        @start = start
        @indices = []

        line
          .each_char
          .with_index(start) do |char, index|
            char.bytesize.times { @indices << index }
          end
      end

      # Technically it's possible for the column index to be a negative value if
      # there's a BOM at the beginning of the file, which is the reason we need
      # to compare it to 0 here.
      def [](byteindex)
        indices[[byteindex, 0].max]
      end
    end

    # This represents all of the tokens coming back from the lexer. It is
    # replacing a simple array because it keeps track of the last deleted token
    # from the list for better error messages.
    class TokenList
      attr_reader :tokens, :last_deleted

      def initialize
        @tokens = []
        @last_deleted = nil
      end

      def <<(token)
        tokens << token
      end

      def [](index)
        tokens[index]
      end

      def any?(&block)
        tokens.any?(&block)
      end

      def reverse_each(&block)
        tokens.reverse_each(&block)
      end

      def rindex(&block)
        tokens.rindex(&block)
      end

      def delete(value)
        @last_deleted = tokens.delete(value) || @last_deleted
      end

      def delete_at(index)
        @last_deleted = tokens.delete_at(index)
      end
    end

    # [String] the source being parsed
    attr_reader :source

    # [Array[ SingleByteString | MultiByteString ]] the list of objects that
    # represent the start of each line in character offsets
    attr_reader :line_counts

    # [Array[ untyped ]] a running list of tokens that have been found in the
    # source. This list changes a lot as certain nodes will "consume" these
    # tokens to determine their bounds.
    attr_reader :tokens

    # [Array[ Comment | EmbDoc ]] the list of comments that have been found
    # while parsing the source.
    attr_reader :comments

    def initialize(source, *)
      super

      # We keep the source around so that we can refer back to it when we're
      # generating the AST. Sometimes it's easier to just reference the source
      # string when you want to check if it contains a certain character, for
      # example.
      @source = source

      # This is the full set of comments that have been found by the parser.
      # It's a running list. At the end of every block of statements, they will
      # go in and attempt to grab any comments that are on their own line and
      # turn them into regular statements. So at the end of parsing the only
      # comments left in here will be comments on lines that also contain code.
      @comments = []

      # This is the current embdoc (comments that start with =begin and end with
      # =end). Since they can't be nested, there's no need for a stack here, as
      # there can only be one active. These end up getting dumped into the
      # comments list before getting picked up by the statements that surround
      # them.
      @embdoc = nil

      # This is an optional node that can be present if the __END__ keyword is
      # used in the file. In that case, this will represent the content after
      # that keyword.
      @__end__ = nil

      # Heredocs can actually be nested together if you're using interpolation,
      # so this is a stack of heredoc nodes that are currently being created.
      # When we get to the token that finishes off a heredoc node, we pop the
      # top one off. If there are others surrounding it, then the body events
      # will now be added to the correct nodes.
      @heredocs = []

      # This is a running list of tokens that have fired. It's useful mostly for
      # maintaining location information. For example, if you're inside the
      # handle of a def event, then in order to determine where the AST node
      # started, you need to look backward in the tokens to find a def keyword.
      # Most of the time, when a parser event consumes one of these events, it
      # will be deleted from the list. So ideally, this list stays pretty short
      # over the course of parsing a source string.
      @tokens = TokenList.new

      # Here we're going to build up a list of SingleByteString or
      # MultiByteString objects. They're each going to represent a string in the
      # source. They are used by the `char_pos` method to determine where we are
      # in the source string.
      @line_counts = []
      last_index = 0

      @source.each_line do |line|
        @line_counts << if line.size == line.bytesize
          SingleByteString.new(last_index)
        else
          MultiByteString.new(last_index, line)
        end

        last_index += line.size
      end

      # Make sure line counts is filled out with the first and last line at
      # minimum so that it has something to compare against if the parser is in
      # a lineno=2 state for an empty file.
      @line_counts << SingleByteString.new(0) if @line_counts.empty?
      @line_counts << SingleByteString.new(last_index)
    end

    private

    # --------------------------------------------------------------------------
    # :section: Helper methods
    # The following methods are used by the ripper event handlers to either
    # determine their bounds or query other nodes.
    # --------------------------------------------------------------------------

    # This represents the current place in the source string that we've gotten
    # to so far. We have a memoized line_counts object that we can use to get
    # the number of characters that we've had to go through to get to the
    # beginning of this line, then we add the number of columns into this line
    # that we've gone through.
    def char_pos
      line_counts[lineno - 1][column]
    end

    # This represents the current column we're in relative to the beginning of
    # the current line.
    def current_column
      line = line_counts[lineno - 1]
      line[column].to_i - line.start
    end

    # Returns the current location that is being looked at for the parser for
    # the purpose of locating the error.
    def find_token_error(location)
      if location
        # If we explicitly passed a location into this find_token_error method,
        # that means that's the source of the error, so we'll use that
        # information for our error object.
        lineno = location.start_line
        [lineno, location.start_char - line_counts[lineno - 1].start]
      elsif lineno && column
        # If there is a line number associated with the current ripper state,
        # then we'll use that information to generate the error.
        [lineno, column]
      elsif (location = tokens.last_deleted&.location)
        # If we've already deleted a token from the list of tokens that we are
        # consuming, then we'll fall back to that token's location.
        lineno = location.start_line
        [lineno, location.start_char - line_counts[lineno - 1].start]
      else
        # Finally, it's possible that when we hit this error the parsing thread
        # for ripper has died. In that case, lineno and column both return nil.
        # So we're just going to set it to line 1, column 0 in the hopes that
        # that makes any sense.
        [1, 0]
      end
    end

    # As we build up a list of tokens, we'll periodically need to go backwards
    # and find the ones that we've already hit in order to determine the
    # location information for nodes that use them. For example, if you have a
    # module node then you'll look backward for a kw token to determine your
    # start location.
    #
    # This works with nesting since we're deleting tokens from the list once
    # they've been used up. For example if you had nested module declarations
    # then the innermost declaration would grab the last kw node that matches
    # "module" (which would happen to be the innermost keyword). Then the outer
    # one would only be able to grab the first one. In this way all of the
    # tokens act as their own stack.
    #
    # If we're expecting to be able to find a token and consume it, but can't
    # actually find it, then we need to raise an error. This is _usually_ caused
    # by a syntax error in the source that we're printing. It could also be
    # caused by accidentally attempting to consume a token twice by two
    # different parser event handlers.

    def find_token(type)
      index = tokens.rindex { |token| token.is_a?(type) }
      tokens[index] if index
    end

    def find_token_between(type, left, right)
      bounds = left.location.end_char...right.location.start_char
      index =
        tokens.rindex do |token|
          char = token.location.start_char
          break if char < bounds.begin

          token.is_a?(type) && bounds.cover?(char)
        end

      tokens[index] if index
    end

    def find_keyword(name)
      index = tokens.rindex { |token| token.is_a?(Kw) && (token.name == name) }
      tokens[index] if index
    end

    def find_keyword_between(name, left, right)
      bounds = left.end_char...right.start_char
      index =
        tokens.rindex do |token|
          char = token.location.start_char
          break if char < bounds.begin

          token.is_a?(Kw) && (token.name == name) && bounds.cover?(char)
        end

      tokens[index] if index
    end

    def find_operator(name)
      index = tokens.rindex { |token| token.is_a?(Op) && (token.name == name) }
      tokens[index] if index
    end

    def consume_error(name, location)
      message = "Cannot find expected #{name}"
      raise ParseError.new(message, *find_token_error(location))
    end

    def consume_token(type)
      index = tokens.rindex { |token| token.is_a?(type) }
      consume_error(type.name.split("::", 2).last, nil) unless index
      tokens.delete_at(index)
    end

    def consume_tstring_end(location)
      index = tokens.rindex { |token| token.is_a?(TStringEnd) }
      consume_error("string ending", location) unless index
      tokens.delete_at(index)
    end

    def consume_keyword(name)
      index = tokens.rindex { |token| token.is_a?(Kw) && (token.name == name) }
      consume_error(name, nil) unless index
      tokens.delete_at(index)
    end

    def consume_operator(name)
      index = tokens.rindex { |token| token.is_a?(Op) && (token.name == name) }
      consume_error(name, nil) unless index
      tokens.delete_at(index)
    end

    # A helper function to find a :: operator. We do special handling instead of
    # using find_token here because we don't pop off all of the :: operators so
    # you could end up getting the wrong information if you have for instance
    # ::X::Y::Z.
    def find_colon2_before(const)
      index =
        tokens.rindex do |token|
          token.is_a?(Op) && token.value == "::" &&
            token.location.start_char < const.location.start_char
        end

      tokens[index]
    end

    # Finds the next position in the source string that begins a statement. This
    # is used to bind statements lists and make sure they don't include a
    # preceding comment. For example, we want the following comment to be
    # attached to the class node and not the statement node:
    #
    #     class Foo # :nodoc:
    #       ...
    #     end
    #
    # By finding the next non-space character, we can make sure that the bounds
    # of the statement list are correct.
    def find_next_statement_start(position)
      maximum = source.length

      position.upto(maximum) do |pound_index|
        case source[pound_index]
        when "#"
          return source.index("\n", pound_index + 1) || maximum
        when " "
          # continue
        else
          return position
        end
      end
    end

    # --------------------------------------------------------------------------
    # :section: Ripper event handlers
    # The following methods all handle a dispatched ripper event.
    # --------------------------------------------------------------------------

    # :call-seq:
    #   on_BEGIN: (Statements statements) -> BEGINBlock
    def on_BEGIN(statements)
      lbrace = consume_token(LBrace)
      rbrace = consume_token(RBrace)

      start_char = find_next_statement_start(lbrace.location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[lbrace.location.start_line - 1].start,
        rbrace.location.start_char,
        rbrace.location.start_column
      )

      keyword = consume_keyword(:BEGIN)

      BEGINBlock.new(
        lbrace: lbrace,
        statements: statements,
        location: keyword.location.to(rbrace.location)
      )
    end

    # :call-seq:
    #   on_CHAR: (String value) -> CHAR
    def on_CHAR(value)
      CHAR.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_END: (Statements statements) -> ENDBlock
    def on_END(statements)
      lbrace = consume_token(LBrace)
      rbrace = consume_token(RBrace)

      start_char = find_next_statement_start(lbrace.location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[lbrace.location.start_line - 1].start,
        rbrace.location.start_char,
        rbrace.location.start_column
      )

      keyword = consume_keyword(:END)

      ENDBlock.new(
        lbrace: lbrace,
        statements: statements,
        location: keyword.location.to(rbrace.location)
      )
    end

    # :call-seq:
    #   on___end__: (String value) -> EndContent
    def on___end__(value)
      @__end__ =
        EndContent.new(
          value: source[(char_pos + value.length)..],
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )
    end

    # :call-seq:
    #   on_alias: (
    #     (DynaSymbol | SymbolLiteral) left,
    #     (DynaSymbol | SymbolLiteral) right
    #   ) -> AliasNode
    def on_alias(left, right)
      keyword = consume_keyword(:alias)

      AliasNode.new(
        left: left,
        right: right,
        location: keyword.location.to(right.location)
      )
    end

    # :call-seq:
    #   on_aref: (untyped collection, (nil | Args) index) -> ARef
    def on_aref(collection, index)
      consume_token(LBracket)
      rbracket = consume_token(RBracket)

      ARef.new(
        collection: collection,
        index: index,
        location: collection.location.to(rbracket.location)
      )
    end

    # :call-seq:
    #   on_aref_field: (
    #     untyped collection,
    #     (nil | Args) index
    #   ) -> ARefField
    def on_aref_field(collection, index)
      consume_token(LBracket)
      rbracket = consume_token(RBracket)

      ARefField.new(
        collection: collection,
        index: index,
        location: collection.location.to(rbracket.location)
      )
    end

    # def on_arg_ambiguous(value)
    #   value
    # end

    # :call-seq:
    #   on_arg_paren: (
    #     (nil | Args | ArgsForward) arguments
    #   ) -> ArgParen
    def on_arg_paren(arguments)
      lparen = consume_token(LParen)
      rparen = consume_token(RParen)

      # If the arguments exceed the ending of the parentheses, then we know we
      # have a heredoc in the arguments, and we need to use the bounds of the
      # arguments to determine how large the arg_paren is.
      ending =
        if arguments && arguments.location.end_line > rparen.location.end_line
          arguments
        else
          rparen
        end

      ArgParen.new(
        arguments: arguments,
        location: lparen.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_args_add: (Args arguments, untyped argument) -> Args
    def on_args_add(arguments, argument)
      if arguments.parts.empty?
        # If this is the first argument being passed into the list of arguments,
        # then we're going to use the bounds of the argument to override the
        # parent node's location since this will be more accurate.
        Args.new(parts: [argument], location: argument.location)
      else
        # Otherwise we're going to update the existing list with the argument
        # being added as well as the new end bounds.
        Args.new(
          parts: arguments.parts << argument,
          location: arguments.location.to(argument.location)
        )
      end
    end

    # :call-seq:
    #   on_args_add_block: (
    #     Args arguments,
    #     (false | untyped) block
    #   ) -> Args
    def on_args_add_block(arguments, block)
      end_char = arguments.parts.any? && arguments.location.end_char

      # First, see if there is an & operator that could potentially be
      # associated with the block part of this args_add_block. If there is not,
      # then just return the arguments.
      index =
        tokens.rindex do |token|
          # If there are any arguments and the operator we found from the list
          # is not after them, then we're going to return the arguments as-is
          # because we're looking at an & that occurs before the arguments are
          # done.
          return arguments if end_char && token.location.start_char < end_char
          token.is_a?(Op) && (token.name == :&)
        end

      return arguments unless index

      # Now we know we have an & operator, so we're going to delete it from the
      # list of tokens to make sure it doesn't get confused with anything else.
      operator = tokens.delete_at(index)

      # Construct the location that represents the block argument.
      location = operator.location
      location = operator.location.to(block.location) if block

      # Otherwise, we're looking at an actual block argument (with or without a
      # block, which could be missing because it could be a bare & since 3.1.0).
      arg_block = ArgBlock.new(value: block, location: location)

      Args.new(
        parts: arguments.parts << arg_block,
        location: arguments.location.to(location)
      )
    end

    # :call-seq:
    #   on_args_add_star: (Args arguments, untyped star) -> Args
    def on_args_add_star(arguments, argument)
      beginning = consume_operator(:*)
      ending = argument || beginning

      location =
        if arguments.parts.empty?
          ending.location
        else
          arguments.location.to(ending.location)
        end

      arg_star =
        ArgStar.new(
          value: argument,
          location: beginning.location.to(ending.location)
        )

      Args.new(parts: arguments.parts << arg_star, location: location)
    end

    # :call-seq:
    #   on_args_forward: () -> ArgsForward
    def on_args_forward
      op = consume_operator(:"...")

      ArgsForward.new(location: op.location)
    end

    # :call-seq:
    #   on_args_new: () -> Args
    def on_args_new
      Args.new(
        parts: [],
        location:
          Location.fixed(line: lineno, column: current_column, char: char_pos)
      )
    end

    # :call-seq:
    #   on_array: ((nil | Args) contents) ->
    #     ArrayLiteral | QSymbols | QWords | Symbols | Words
    def on_array(contents)
      if !contents || contents.is_a?(Args)
        lbracket = consume_token(LBracket)
        rbracket = consume_token(RBracket)

        ArrayLiteral.new(
          lbracket: lbracket,
          contents: contents,
          location: lbracket.location.to(rbracket.location)
        )
      else
        tstring_end = consume_tstring_end(contents.beginning.location)

        contents.class.new(
          beginning: contents.beginning,
          elements: contents.elements,
          location: contents.location.to(tstring_end.location)
        )
      end
    end

    # Ugh... I really do not like this class. Basically, ripper doesn't provide
    # enough information about where pins are located in the tree. It only gives
    # events for ^ ops and var_ref nodes. You have to piece it together
    # yourself.
    #
    # Note that there are edge cases here that we straight up do not address,
    # because I honestly think it's going to be faster to write a new parser
    # than to address them. For example, this will not work properly:
    #
    #     foo in ^((bar = 0; bar; baz))
    #
    # If someone actually does something like that, we'll have to find another
    # way to make this work.
    class PinVisitor < Visitor
      attr_reader :pins, :stack

      def initialize(pins)
        @pins = pins
        @stack = []
      end

      def visit(node)
        return if pins.empty?
        stack << node
        super
        stack.pop
      end

      visit_methods do
        def visit_var_ref(node)
          node.pin(stack[-2], pins.shift)
        end
      end

      def self.visit(node, tokens)
        start_char = node.start_char
        allocated = []

        tokens.reverse_each do |token|
          char = token.location.start_char
          break if char <= start_char

          if token.is_a?(Op) && token.value == "^"
            allocated.unshift(tokens.delete(token))
          end
        end

        new(allocated).visit(node) if allocated.any?
      end
    end

    # :call-seq:
    #   on_aryptn: (
    #     (nil | VarRef) constant,
    #     (nil | Array[untyped]) requireds,
    #     (nil | VarField) rest,
    #     (nil | Array[untyped]) posts
    #   ) -> AryPtn
    def on_aryptn(constant, requireds, rest, posts)
      lbracket = find_token(LBracket)
      lbracket ||= find_token(LParen) if constant

      rbracket = find_token(RBracket)
      rbracket ||= find_token(RParen) if constant

      parts = [constant, lbracket, *requireds, rest, *posts, rbracket].compact

      # The location is going to be determined by the first part to the last
      # part. This includes potential brackets.
      location = parts[0].location.to(parts[-1].location)

      # Now that we have the location calculated, we can remove the brackets
      # from the list of tokens.
      tokens.delete(lbracket) if lbracket
      tokens.delete(rbracket) if rbracket

      # If there is a plain *, then we're going to fix up the location of it
      # here because it currently doesn't have anything to use for its precise
      # location. If we hit a comma, then we've gone too far.
      if rest.is_a?(VarField) && rest.value.nil?
        tokens.rindex do |rtoken|
          case rtoken
          when Comma
            break
          when Op
            if rtoken.value == "*"
              rest = VarField.new(value: nil, location: rtoken.location)
              break
            end
          end
        end
      end

      AryPtn.new(
        constant: constant,
        requireds: requireds || [],
        rest: rest,
        posts: posts || [],
        location: location
      )
    end

    # :call-seq:
    #   on_assign: (
    #     (
    #       ARefField |
    #       ConstPathField |
    #       Field |
    #       TopConstField |
    #       VarField
    #     ) target,
    #     untyped value
    #   ) -> Assign
    def on_assign(target, value)
      Assign.new(
        target: target,
        value: value,
        location: target.location.to(value.location)
      )
    end

    # :call-seq:
    #   on_assoc_new: (untyped key, untyped value) -> Assoc
    def on_assoc_new(key, value)
      location = key.location
      location = location.to(value.location) if value

      Assoc.new(key: key, value: value, location: location)
    end

    # :call-seq:
    #   on_assoc_splat: (untyped value) -> AssocSplat
    def on_assoc_splat(value)
      operator = consume_operator(:**)

      AssocSplat.new(
        value: value,
        location: operator.location.to((value || operator).location)
      )
    end

    # def on_assoclist_from_args(assocs)
    #   assocs
    # end

    # :call-seq:
    #   on_backref: (String value) -> Backref
    def on_backref(value)
      Backref.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_backtick: (String value) -> Backtick
    def on_backtick(value)
      node =
        Backtick.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_bare_assoc_hash: (
    #     Array[AssocNew | AssocSplat] assocs
    #   ) -> BareAssocHash
    def on_bare_assoc_hash(assocs)
      BareAssocHash.new(
        assocs: assocs,
        location: assocs[0].location.to(assocs[-1].location)
      )
    end

    # :call-seq:
    #   on_begin: (untyped bodystmt) -> Begin | PinnedBegin
    def on_begin(bodystmt)
      pin = find_operator(:^)

      if pin && pin.location.start_char < bodystmt.location.start_char
        tokens.delete(pin)
        consume_token(LParen)

        rparen = consume_token(RParen)
        location = pin.location.to(rparen.location)

        PinnedBegin.new(statement: bodystmt, location: location)
      else
        keyword = consume_keyword(:begin)
        end_location =
          if bodystmt.else_clause
            bodystmt.location
          else
            consume_keyword(:end).location
          end

        bodystmt.bind(
          self,
          find_next_statement_start(keyword.location.end_char),
          keyword.location.end_column,
          end_location.end_char,
          end_location.end_column
        )

        location = keyword.location.to(end_location)
        Begin.new(bodystmt: bodystmt, location: location)
      end
    end

    # :call-seq:
    #   on_binary: (
    #     untyped left,
    #     (Op | Symbol) operator,
    #     untyped right
    #   ) -> Binary
    def on_binary(left, operator, right)
      if operator.is_a?(Symbol)
        # Here, we're going to search backward for the token that's between the
        # two operands that matches the operator so we can delete it from the
        # list.
        range = (left.location.end_char + 1)...right.location.start_char
        index =
          tokens.rindex do |token|
            token.is_a?(Op) && token.name == operator &&
              range.cover?(token.location.start_char)
          end

        tokens.delete_at(index) if index
      else
        # On most Ruby implementations, operator is a Symbol that represents
        # that operation being performed. For instance in the example `1 < 2`,
        # the `operator` object would be `:<`. However, on JRuby, it's an `@op`
        # node, so here we're going to explicitly convert it into the same
        # normalized form.
        operator = tokens.delete(operator).value
      end

      Binary.new(
        left: left,
        operator: operator,
        right: right,
        location: left.location.to(right.location)
      )
    end

    # :call-seq:
    #   on_block_var: (Params params, (nil | Array[Ident]) locals) -> BlockVar
    def on_block_var(params, locals)
      index =
        tokens.rindex { |node| node.is_a?(Op) && %w[| ||].include?(node.value) }

      ending = tokens.delete_at(index)
      beginning = ending.value == "||" ? ending : consume_operator(:|)

      # If there are no parameters, then we didn't have anything to base the
      # location information of off. Now that we have an opening of the
      # block, we can correct this.
      if params.empty?
        start_line = params.location.start_line
        start_char =
          (
            if beginning.value == "||"
              beginning.location.start_char
            else
              find_next_statement_start(beginning.location.end_char)
            end
          )

        location =
          Location.fixed(
            line: start_line,
            char: start_char,
            column: start_char - line_counts[start_line - 1].start
          )

        params = params.copy(location: location)
      end

      BlockVar.new(
        params: params,
        locals: locals || [],
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_blockarg: (Ident name) -> BlockArg
    def on_blockarg(name)
      operator = consume_operator(:&)

      location = operator.location
      location = location.to(name.location) if name

      BlockArg.new(name: name, location: location)
    end

    # :call-seq:
    #   on_bodystmt: (
    #     Statements statements,
    #     (nil | Rescue) rescue_clause,
    #     (nil | Statements) else_clause,
    #     (nil | Ensure) ensure_clause
    #   ) -> BodyStmt
    def on_bodystmt(statements, rescue_clause, else_clause, ensure_clause)
      # In certain versions of Ruby, the `statements` argument can be any node
      # in the case that we're inside of an endless method definition. In this
      # case we'll wrap it in a Statements node to be consistent.
      unless statements.is_a?(Statements)
        statements =
          Statements.new(body: [statements], location: statements.location)
      end

      parts = [statements, rescue_clause, else_clause, ensure_clause].compact

      BodyStmt.new(
        statements: statements,
        rescue_clause: rescue_clause,
        else_keyword: else_clause && consume_keyword(:else),
        else_clause: else_clause,
        ensure_clause: ensure_clause,
        location: parts.first.location.to(parts.last.location)
      )
    end

    # :call-seq:
    #   on_brace_block: (
    #     (nil | BlockVar) block_var,
    #     Statements statements
    #   ) -> BlockNode
    def on_brace_block(block_var, statements)
      lbrace = consume_token(LBrace)
      rbrace = consume_token(RBrace)
      location = (block_var || lbrace).location

      start_char = find_next_statement_start(location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[location.start_line - 1].start,
        rbrace.location.start_char,
        rbrace.location.start_column
      )

      location =
        Location.new(
          start_line: lbrace.location.start_line,
          start_char: lbrace.location.start_char,
          start_column: lbrace.location.start_column,
          end_line: [
            rbrace.location.end_line,
            statements.location.end_line
          ].max,
          end_char: rbrace.location.end_char,
          end_column: rbrace.location.end_column
        )

      BlockNode.new(
        opening: lbrace,
        block_var: block_var,
        bodystmt: statements,
        location: location
      )
    end

    # :call-seq:
    #   on_break: (Args arguments) -> Break
    def on_break(arguments)
      keyword = consume_keyword(:break)

      location = keyword.location
      location = location.to(arguments.location) if arguments.parts.any?

      Break.new(arguments: arguments, location: location)
    end

    # :call-seq:
    #   on_call: (
    #     untyped receiver,
    #     (:"::" | Op | Period) operator,
    #     (:call | Backtick | Const | Ident | Op) message
    #   ) -> CallNode
    def on_call(receiver, operator, message)
      ending =
        if message != :call
          message
        elsif operator != :"::"
          operator
        else
          receiver
        end

      CallNode.new(
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: nil,
        location: receiver.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_case: (untyped value, untyped consequent) -> Case | RAssign
    def on_case(value, consequent)
      if value && (operator = find_keyword(:in) || find_operator(:"=>")) &&
           (value.location.end_char...consequent.location.start_char).cover?(
             operator.location.start_char
           )
        tokens.delete(operator)

        node =
          RAssign.new(
            value: value,
            operator: operator,
            pattern: consequent,
            location: value.location.to(consequent.location)
          )

        PinVisitor.visit(node, tokens)
        node
      else
        keyword = consume_keyword(:case)

        Case.new(
          keyword: keyword,
          value: value,
          consequent: consequent,
          location: keyword.location.to(consequent.location)
        )
      end
    end

    # :call-seq:
    #   on_class: (
    #     (ConstPathRef | ConstRef | TopConstRef) constant,
    #     untyped superclass,
    #     BodyStmt bodystmt
    #   ) -> ClassDeclaration
    def on_class(constant, superclass, bodystmt)
      beginning = consume_keyword(:class)
      ending = consume_keyword(:end)
      location = (superclass || constant).location
      start_char = find_next_statement_start(location.end_char)

      bodystmt.bind(
        self,
        start_char,
        start_char - line_counts[location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      ClassDeclaration.new(
        constant: constant,
        superclass: superclass,
        bodystmt: bodystmt,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_comma: (String value) -> Comma
    def on_comma(value)
      node =
        Comma.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_command: ((Const | Ident) message, Args arguments) -> Command
    def on_command(message, arguments)
      Command.new(
        message: message,
        arguments: arguments,
        block: nil,
        location: message.location.to(arguments.location)
      )
    end

    # :call-seq:
    #   on_command_call: (
    #     untyped receiver,
    #     (:"::" | Op | Period) operator,
    #     (Const | Ident | Op) message,
    #     (nil | Args) arguments
    #   ) -> CommandCall
    def on_command_call(receiver, operator, message, arguments)
      ending = arguments || message

      CommandCall.new(
        receiver: receiver,
        operator: operator,
        message: message,
        arguments: arguments,
        block: nil,
        location: receiver.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_comment: (String value) -> Comment
    def on_comment(value)
      # char is the index of the # character in the source.
      char = char_pos
      location =
        Location.token(
          line: lineno,
          char: char,
          column: current_column,
          size: value.size - 1
        )

      # Loop backward in the source string, starting from the beginning of the
      # comment, and find the first character that is not a space or a tab. If
      # index is -1, this indicates that we've checked all of the characters
      # back to the start of the source, so this comment must be at the
      # beginning of the file.
      #
      # We are purposefully not using rindex or regular expressions here because
      # they check if there are invalid characters, which is actually possible
      # with the use of __END__ syntax.
      index = char - 1
      while index > -1 && (source[index] == "\t" || source[index] == " ")
        index -= 1
      end

      # If we found a character that was not a space or a tab before the comment
      # and it's a newline, then this comment is inline. Otherwise, it stands on
      # its own and can be attached as its own node in the tree.
      inline = index != -1 && source[index] != "\n"
      comment =
        Comment.new(value: value.chomp, inline: inline, location: location)

      @comments << comment
      comment
    end

    # :call-seq:
    #   on_const: (String value) -> Const
    def on_const(value)
      Const.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_const_path_field: (untyped parent, Const constant) ->
    #     ConstPathField | Field
    def on_const_path_field(parent, constant)
      if constant.is_a?(Const)
        ConstPathField.new(
          parent: parent,
          constant: constant,
          location: parent.location.to(constant.location)
        )
      else
        Field.new(
          parent: parent,
          operator: consume_operator(:"::"),
          name: constant,
          location: parent.location.to(constant.location)
        )
      end
    end

    # :call-seq:
    #   on_const_path_ref: (untyped parent, Const constant) -> ConstPathRef
    def on_const_path_ref(parent, constant)
      ConstPathRef.new(
        parent: parent,
        constant: constant,
        location: parent.location.to(constant.location)
      )
    end

    # :call-seq:
    #   on_const_ref: (Const constant) -> ConstRef
    def on_const_ref(constant)
      ConstRef.new(constant: constant, location: constant.location)
    end

    # :call-seq:
    #   on_cvar: (String value) -> CVar
    def on_cvar(value)
      CVar.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_def: (
    #     (Backtick | Const | Ident | Kw | Op) name,
    #     (nil | Params | Paren) params,
    #     untyped bodystmt
    #   ) -> DefNode
    def on_def(name, params, bodystmt)
      # Make sure to delete this token in case you're defining something like
      # def class which would lead to this being a kw and causing all kinds of
      # trouble
      tokens.delete(name)

      # Find the beginning of the method definition, which works for single-line
      # and normal method definitions.
      beginning = consume_keyword(:def)

      # If there aren't any params then we need to correct the params node
      # location information
      if params.is_a?(Params) && params.empty?
        end_char = name.location.end_char
        end_column = name.location.end_column
        location =
          Location.new(
            start_line: params.location.start_line,
            start_char: end_char,
            start_column: end_column,
            end_line: params.location.end_line,
            end_char: end_char,
            end_column: end_column
          )

        params = Params.new(location: location)
      end

      ending = find_keyword(:end)

      if ending
        tokens.delete(ending)
        start_char = find_next_statement_start(params.location.end_char)

        bodystmt.bind(
          self,
          start_char,
          start_char - line_counts[params.location.start_line - 1].start,
          ending.location.start_char,
          ending.location.start_column
        )

        DefNode.new(
          target: nil,
          operator: nil,
          name: name,
          params: params,
          bodystmt: bodystmt,
          location: beginning.location.to(ending.location)
        )
      else
        # In Ruby >= 3.1.0, this is a BodyStmt that wraps a single statement in
        # the statements list. Before, it was just the individual statement.
        statement = bodystmt.is_a?(BodyStmt) ? bodystmt.statements : bodystmt

        DefNode.new(
          target: nil,
          operator: nil,
          name: name,
          params: params,
          bodystmt: statement,
          location: beginning.location.to(bodystmt.location)
        )
      end
    end

    # :call-seq:
    #   on_defined: (untyped value) -> Defined
    def on_defined(value)
      beginning = consume_keyword(:defined?)
      ending = value

      range = beginning.location.end_char...value.location.start_char
      if source[range].include?("(")
        consume_token(LParen)
        ending = consume_token(RParen)
      end

      Defined.new(
        value: value,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_defs: (
    #     untyped target,
    #     (Op | Period) operator,
    #     (Backtick | Const | Ident | Kw | Op) name,
    #     (Params | Paren) params,
    #     BodyStmt bodystmt
    #   ) -> DefNode
    def on_defs(target, operator, name, params, bodystmt)
      # Make sure to delete this token in case you're defining something
      # like def class which would lead to this being a kw and causing all kinds
      # of trouble
      tokens.delete(name)

      # If there aren't any params then we need to correct the params node
      # location information
      if params.is_a?(Params) && params.empty?
        end_char = name.location.end_char
        end_column = name.location.end_column
        location =
          Location.new(
            start_line: params.location.start_line,
            start_char: end_char,
            start_column: end_column,
            end_line: params.location.end_line,
            end_char: end_char,
            end_column: end_column
          )

        params = Params.new(location: location)
      end

      beginning = consume_keyword(:def)
      ending = find_keyword(:end)

      if ending
        tokens.delete(ending)
        start_char = find_next_statement_start(params.location.end_char)

        bodystmt.bind(
          self,
          start_char,
          start_char - line_counts[params.location.start_line - 1].start,
          ending.location.start_char,
          ending.location.start_column
        )

        DefNode.new(
          target: target,
          operator: operator,
          name: name,
          params: params,
          bodystmt: bodystmt,
          location: beginning.location.to(ending.location)
        )
      else
        # In Ruby >= 3.1.0, this is a BodyStmt that wraps a single statement in
        # the statements list. Before, it was just the individual statement.
        statement = bodystmt.is_a?(BodyStmt) ? bodystmt.statements : bodystmt

        DefNode.new(
          target: target,
          operator: operator,
          name: name,
          params: params,
          bodystmt: statement,
          location: beginning.location.to(bodystmt.location)
        )
      end
    end

    # :call-seq:
    #   on_do_block: (BlockVar block_var, BodyStmt bodystmt) -> BlockNode
    def on_do_block(block_var, bodystmt)
      beginning = consume_keyword(:do)
      ending = consume_keyword(:end)
      location = (block_var || beginning).location
      start_char = find_next_statement_start(location.end_char)

      bodystmt.bind(
        self,
        start_char,
        start_char - line_counts[location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      BlockNode.new(
        opening: beginning,
        block_var: block_var,
        bodystmt: bodystmt,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_dot2: ((nil | untyped) left, (nil | untyped) right) -> RangeNode
    def on_dot2(left, right)
      operator = consume_operator(:"..")

      beginning = left || operator
      ending = right || operator

      RangeNode.new(
        left: left,
        operator: operator,
        right: right,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_dot3: ((nil | untyped) left, (nil | untyped) right) -> RangeNode
    def on_dot3(left, right)
      operator = consume_operator(:"...")

      beginning = left || operator
      ending = right || operator

      RangeNode.new(
        left: left,
        operator: operator,
        right: right,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_dyna_symbol: (StringContent string_content) -> DynaSymbol
    def on_dyna_symbol(string_content)
      if (symbeg = find_token(SymBeg))
        # A normal dynamic symbol
        tokens.delete(symbeg)
        tstring_end = consume_tstring_end(symbeg.location)

        DynaSymbol.new(
          quote: symbeg.value,
          parts: string_content.parts,
          location: symbeg.location.to(tstring_end.location)
        )
      else
        # A dynamic symbol as a hash key
        tstring_beg = consume_token(TStringBeg)
        label_end = consume_token(LabelEnd)

        DynaSymbol.new(
          parts: string_content.parts,
          quote: label_end.value[0],
          location: tstring_beg.location.to(label_end.location)
        )
      end
    end

    # :call-seq:
    #   on_else: (Statements statements) -> Else
    def on_else(statements)
      keyword = consume_keyword(:else)

      # else can either end with an end keyword (in which case we'll want to
      # consume that event) or it can end with an ensure keyword (in which case
      # we'll leave that to the ensure to handle).
      index =
        tokens.rindex do |token|
          token.is_a?(Kw) && %w[end ensure].include?(token.value)
        end

      if index.nil?
        message = "Cannot find expected else ending"
        raise ParseError.new(message, *find_token_error(keyword.location))
      end

      node = tokens[index]
      ending = node.value == "end" ? tokens.delete_at(index) : node

      start_char = find_next_statement_start(keyword.location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[keyword.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      Else.new(
        keyword: keyword,
        statements: statements,
        location: keyword.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_elsif: (
    #     untyped predicate,
    #     Statements statements,
    #     (nil | Elsif | Else) consequent
    #   ) -> Elsif
    def on_elsif(predicate, statements, consequent)
      beginning = consume_keyword(:elsif)
      ending = consequent || consume_keyword(:end)

      delimiter =
        find_keyword_between(:then, predicate, statements) ||
          find_token_between(Semicolon, predicate, statements)

      tokens.delete(delimiter) if delimiter
      start_char =
        find_next_statement_start((delimiter || predicate).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char - line_counts[predicate.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      Elsif.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_embdoc: (String value) -> EmbDoc
    def on_embdoc(value)
      @embdoc.value << value
      @embdoc
    end

    # :call-seq:
    #   on_embdoc_beg: (String value) -> EmbDoc
    def on_embdoc_beg(value)
      @embdoc =
        EmbDoc.new(
          value: value,
          location:
            Location.fixed(line: lineno, column: current_column, char: char_pos)
        )
    end

    # :call-seq:
    #   on_embdoc_end: (String value) -> EmbDoc
    def on_embdoc_end(value)
      location = @embdoc.location
      embdoc =
        EmbDoc.new(
          value: @embdoc.value << value.chomp,
          location:
            Location.new(
              start_line: location.start_line,
              start_char: location.start_char,
              start_column: location.start_column,
              end_line: lineno,
              end_char: char_pos + value.length - 1,
              end_column: current_column + value.length - 1
            )
        )

      @comments << embdoc
      @embdoc = nil

      embdoc
    end

    # :call-seq:
    #   on_embexpr_beg: (String value) -> EmbExprBeg
    def on_embexpr_beg(value)
      node =
        EmbExprBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_embexpr_end: (String value) -> EmbExprEnd
    def on_embexpr_end(value)
      node =
        EmbExprEnd.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_embvar: (String value) -> EmbVar
    def on_embvar(value)
      node =
        EmbVar.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_ensure: (Statements statements) -> Ensure
    def on_ensure(statements)
      keyword = consume_keyword(:ensure)

      # We don't want to consume the :@kw event, because that would break
      # def..ensure..end chains.
      ending = find_keyword(:end)
      start_char = find_next_statement_start(keyword.location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[keyword.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      Ensure.new(
        keyword: keyword,
        statements: statements,
        location: keyword.location.to(ending.location)
      )
    end

    # The handler for this event accepts no parameters (though in previous
    # versions of Ruby it accepted a string literal with a value of ",").
    #
    # :call-seq:
    #   on_excessed_comma: () -> ExcessedComma
    def on_excessed_comma(*)
      comma = consume_token(Comma)

      ExcessedComma.new(value: comma.value, location: comma.location)
    end

    # :call-seq:
    #   on_fcall: ((Const | Ident) value) -> CallNode
    def on_fcall(value)
      CallNode.new(
        receiver: nil,
        operator: nil,
        message: value,
        arguments: nil,
        location: value.location
      )
    end

    # :call-seq:
    #   on_field: (
    #     untyped parent,
    #     (:"::" | Op | Period) operator
    #     (Const | Ident) name
    #   ) -> Field
    def on_field(parent, operator, name)
      Field.new(
        parent: parent,
        operator: operator,
        name: name,
        location: parent.location.to(name.location)
      )
    end

    # :call-seq:
    #   on_float: (String value) -> FloatLiteral
    def on_float(value)
      FloatLiteral.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_fndptn: (
    #     (nil | untyped) constant,
    #     VarField left,
    #     Array[untyped] values,
    #     VarField right
    #   ) -> FndPtn
    def on_fndptn(constant, left, values, right)
      # The left and right of a find pattern are always going to be splats, so
      # we're going to consume the * operators and use their location
      # information to extend the location of the splats.
      right, left =
        [right, left].map do |node|
          operator = consume_operator(:*)
          location =
            if node.value
              operator.location.to(node.location)
            else
              operator.location
            end

          node.copy(location: location)
        end

      # The opening of this find pattern is either going to be a left bracket, a
      # right left parenthesis, or the left splat. We're going to use this to
      # determine how to find the closing of the pattern, as well as determining
      # the location of the node.
      opening = find_token(LBracket) || find_token(LParen) || left

      # The closing is based on the opening, which is either the matched
      # punctuation or the right splat.
      closing =
        case opening
        when LBracket
          tokens.delete(opening)
          consume_token(RBracket)
        when LParen
          tokens.delete(opening)
          consume_token(RParen)
        else
          right
        end

      FndPtn.new(
        constant: constant,
        left: left,
        values: values,
        right: right,
        location: (constant || opening).location.to(closing.location)
      )
    end

    # :call-seq:
    #   on_for: (
    #     (MLHS | VarField) value,
    #     untyped collection,
    #     Statements statements
    #   ) -> For
    def on_for(index, collection, statements)
      beginning = consume_keyword(:for)
      in_keyword = consume_keyword(:in)
      ending = consume_keyword(:end)

      delimiter =
        find_keyword_between(:do, collection, ending) ||
          find_token_between(Semicolon, collection, ending)

      tokens.delete(delimiter) if delimiter

      start_char =
        find_next_statement_start((delimiter || collection).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char -
          line_counts[(delimiter || collection).location.end_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      if index.is_a?(MLHS)
        comma_range = index.location.end_char...in_keyword.location.start_char
        index.comma = true if source[comma_range].strip.start_with?(",")
      end

      For.new(
        index: index,
        collection: collection,
        statements: statements,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_gvar: (String value) -> GVar
    def on_gvar(value)
      GVar.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_hash: ((nil | Array[AssocNew | AssocSplat]) assocs) -> HashLiteral
    def on_hash(assocs)
      lbrace = consume_token(LBrace)
      rbrace = consume_token(RBrace)

      HashLiteral.new(
        lbrace: lbrace,
        assocs: assocs || [],
        location: lbrace.location.to(rbrace.location)
      )
    end

    # :call-seq:
    #   on_heredoc_beg: (String value) -> HeredocBeg
    def on_heredoc_beg(value)
      location =
        Location.token(
          line: lineno,
          char: char_pos,
          column: current_column,
          size: value.size
        )

      # Here we're going to artificially create an extra node type so that if
      # there are comments after the declaration of a heredoc, they get printed.
      beginning = HeredocBeg.new(value: value, location: location)
      @heredocs << Heredoc.new(beginning: beginning, location: location)

      beginning
    end

    # :call-seq:
    #   on_heredoc_dedent: (StringContent string, Integer width) -> Heredoc
    def on_heredoc_dedent(string, width)
      heredoc = @heredocs[-1]

      @heredocs[-1] = Heredoc.new(
        beginning: heredoc.beginning,
        ending: heredoc.ending,
        dedent: width,
        parts: string.parts,
        location: heredoc.location
      )
    end

    # :call-seq:
    #   on_heredoc_end: (String value) -> Heredoc
    def on_heredoc_end(value)
      heredoc = @heredocs[-1]

      location =
        Location.token(
          line: lineno,
          char: char_pos,
          column: current_column,
          size: value.size
        )

      heredoc_end = HeredocEnd.new(value: value.chomp, location: location)

      @heredocs[-1] = Heredoc.new(
        beginning: heredoc.beginning,
        ending: heredoc_end,
        dedent: heredoc.dedent,
        parts: heredoc.parts,
        location:
          Location.new(
            start_line: heredoc.location.start_line,
            start_char: heredoc.location.start_char,
            start_column: heredoc.location.start_column,
            end_line: location.end_line,
            end_char: location.end_char,
            end_column: location.end_column
          )
      )
    end

    # :call-seq:
    #   on_hshptn: (
    #     (nil | untyped) constant,
    #     Array[[Label | StringContent, untyped]] keywords,
    #     (nil | VarField) keyword_rest
    #   ) -> HshPtn
    def on_hshptn(constant, keywords, keyword_rest)
      keywords =
        (keywords || []).map do |(label, value)|
          if label.is_a?(Label)
            [label, value]
          else
            tstring_beg_index =
              tokens.rindex do |token|
                token.is_a?(TStringBeg) &&
                  token.location.start_char < label.location.start_char
              end

            tstring_beg = tokens.delete_at(tstring_beg_index)

            label_end_index =
              tokens.rindex do |token|
                token.is_a?(LabelEnd) &&
                  token.location.start_char == label.location.end_char
              end

            label_end = tokens.delete_at(label_end_index)

            [
              DynaSymbol.new(
                parts: label.parts,
                quote: label_end.value[0],
                location: tstring_beg.location.to(label_end.location)
              ),
              value
            ]
          end
        end

      if keyword_rest
        # We're doing this to delete the token from the list so that it doesn't
        # confuse future patterns by thinking they have an extra ** on the end.
        consume_operator(:**)
      elsif (token = find_operator(:**))
        tokens.delete(token)

        # Create an artificial VarField if we find an extra ** on the end. This
        # means the formatting will be a little more consistent.
        keyword_rest = VarField.new(value: nil, location: token.location)
      end

      parts = [constant, *keywords.flatten(1), keyword_rest].compact

      # If there's no constant, there may be braces, so we're going to look for
      # those to get our bounds.
      unless constant
        lbrace = find_token(LBrace)
        rbrace = find_token(RBrace)

        if lbrace && rbrace
          parts = [lbrace, *parts, rbrace]
          tokens.delete(lbrace)
          tokens.delete(rbrace)
        end
      end

      HshPtn.new(
        constant: constant,
        keywords: keywords,
        keyword_rest: keyword_rest,
        location: parts[0].location.to(parts[-1].location)
      )
    end

    # :call-seq:
    #   on_ident: (String value) -> Ident
    def on_ident(value)
      Ident.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_if: (
    #     untyped predicate,
    #     Statements statements,
    #     (nil | Elsif | Else) consequent
    #   ) -> IfNode
    def on_if(predicate, statements, consequent)
      beginning = consume_keyword(:if)
      ending = consequent || consume_keyword(:end)

      if (keyword = find_keyword_between(:then, predicate, ending))
        tokens.delete(keyword)
      end

      start_char =
        find_next_statement_start((keyword || predicate).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char - line_counts[predicate.location.end_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      IfNode.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_ifop: (untyped predicate, untyped truthy, untyped falsy) -> IfOp
    def on_ifop(predicate, truthy, falsy)
      IfOp.new(
        predicate: predicate,
        truthy: truthy,
        falsy: falsy,
        location: predicate.location.to(falsy.location)
      )
    end

    # :call-seq:
    #   on_if_mod: (untyped predicate, untyped statement) -> IfNode
    def on_if_mod(predicate, statement)
      consume_keyword(:if)

      IfNode.new(
        predicate: predicate,
        statements:
          Statements.new(body: [statement], location: statement.location),
        consequent: nil,
        location: statement.location.to(predicate.location)
      )
    end

    # def on_ignored_nl(value)
    #   value
    # end

    # def on_ignored_sp(value)
    #   value
    # end

    # :call-seq:
    #   on_imaginary: (String value) -> Imaginary
    def on_imaginary(value)
      Imaginary.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_in: (RAssign pattern, nil statements, nil consequent) -> RAssign
    #        | (
    #            untyped pattern,
    #            Statements statements,
    #            (nil | In | Else) consequent
    #          ) -> In
    def on_in(pattern, statements, consequent)
      # Here we have a rightward assignment
      return pattern unless statements

      beginning = consume_keyword(:in)
      ending = consequent || consume_keyword(:end)

      statements_start = pattern
      if (token = find_keyword_between(:then, pattern, statements))
        tokens.delete(token)
        statements_start = token
      end

      start_char =
        find_next_statement_start((token || statements_start).location.end_char)

      # Ripper ignores parentheses on patterns, so we need to do the same in
      # order to attach comments correctly to the pattern.
      if source[start_char] == ")"
        start_char = find_next_statement_start(start_char + 1)
      end

      statements.bind(
        self,
        start_char,
        start_char -
          line_counts[statements_start.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      node =
        In.new(
          pattern: pattern,
          statements: statements,
          consequent: consequent,
          location: beginning.location.to(ending.location)
        )

      PinVisitor.visit(node, tokens)
      node
    end

    # :call-seq:
    #   on_int: (String value) -> Int
    def on_int(value)
      Int.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_ivar: (String value) -> IVar
    def on_ivar(value)
      IVar.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_kw: (String value) -> Kw
    def on_kw(value)
      node =
        Kw.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_kwrest_param: ((nil | Ident) name) -> KwRestParam
    def on_kwrest_param(name)
      location = consume_operator(:**).location
      location = location.to(name.location) if name

      KwRestParam.new(name: name, location: location)
    end

    # :call-seq:
    #   on_label: (String value) -> Label
    def on_label(value)
      Label.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_label_end: (String value) -> LabelEnd
    def on_label_end(value)
      node =
        LabelEnd.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_lambda: (
    #     (Params | Paren) params,
    #     (BodyStmt | Statements) statements
    #   ) -> Lambda
    def on_lambda(params, statements)
      beginning = consume_token(TLambda)
      braces =
        tokens.any? do |token|
          token.is_a?(TLamBeg) &&
            token.location.start_char > beginning.location.start_char
        end

      if braces
        opening = consume_token(TLamBeg)
        closing = consume_token(RBrace)
      else
        opening = consume_keyword(:do)
        closing = consume_keyword(:end)
      end

      # We need to do some special mapping here. Since ripper doesn't support
      # capturing lambda vars, we need to normalize all of that here.
      params =
        if params.is_a?(Paren)
          # In this case we've gotten to the parentheses wrapping a set of
          # parameters case. Here we need to manually scan for lambda locals.
          range = (params.location.start_char + 1)...params.location.end_char
          locals = lambda_locals(source[range])

          location = params.contents.location
          location = location.to(locals.last.location) if locals.any?

          node =
            Paren.new(
              lparen: params.lparen,
              contents:
                LambdaVar.new(
                  params: params.contents,
                  locals: locals,
                  location: location
                ),
              location: params.location
            )

          node.comments.concat(params.comments)
          node
        else
          # If there are no parameters, then we didn't have anything to base the
          # location information of off. Now that we have an opening of the
          # block, we can correct this.
          if params.empty?
            opening_location = opening.location
            location =
              Location.fixed(
                line: opening_location.start_line,
                char: opening_location.start_char,
                column: opening_location.start_column
              )

            params = params.copy(location: location)
          end

          # In this case we've gotten to the plain set of parameters. In this
          # case there cannot be lambda locals, so we will wrap the parameters
          # into a lambda var that has no locals.
          LambdaVar.new(params: params, locals: [], location: params.location)
        end

      start_char = find_next_statement_start(opening.location.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[opening.location.end_line - 1].start,
        closing.location.start_char,
        closing.location.start_column
      )

      Lambda.new(
        params: params,
        statements: statements,
        location: beginning.location.to(closing.location)
      )
    end

    # :call-seq:
    #   on_lambda_var: (Params params, Array[ Ident ] locals) -> LambdaVar
    def on_lambda_var(params, locals)
      location = params.location
      location = location.to(locals.last.location) if locals.any?

      LambdaVar.new(params: params, locals: locals || [], location: location)
    end

    # Ripper doesn't support capturing lambda local variables until 3.2. To
    # mitigate this, we have to parse that code for ourselves. We use the range
    # from the parentheses to find where we _should_ be looking. Then we check
    # if the resulting tokens match a pattern that we determine means that the
    # declaration has block-local variables. Once it does, we parse those out
    # and convert them into Ident nodes.
    def lambda_locals(source)
      tokens = Ripper.lex(source)

      # First, check that we have a semi-colon. If we do, then we can start to
      # parse the tokens _after_ the semicolon.
      index = tokens.rindex { |token| token[1] == :on_semicolon }
      return [] unless index

      # Next, map over the tokens and convert them into Ident nodes. Bail out
      # midway through if we encounter a token we didn't expect. Basically we're
      # making our own mini-parser here. To do that we'll walk through a small
      # state machine:
      #
      #     ┌────────┐               ┌────────┐                ┌─────────┐
      #     │        │               │        │                │┌───────┐│
      # ──> │  item  │ ─── ident ──> │  next  │ ─── rparen ──> ││ final ││
      #     │        │ <── comma ─── │        │                │└───────┘│
      #     └────────┘               └────────┘                └─────────┘
      #        │  ^                     │  ^
      #        └──┘                     └──┘
      #    ignored_nl, sp              nl, sp
      #
      state = :item
      transitions = {
        item: {
          on_ignored_nl: :item,
          on_sp: :item,
          on_ident: :next
        },
        next: {
          on_nl: :next,
          on_sp: :next,
          on_comma: :item,
          on_rparen: :final
        },
        final: {
        }
      }

      parent_line = lineno - 1
      parent_column =
        consume_token(Semicolon).location.start_column - tokens[index][0][1]

      tokens[(index + 1)..].each_with_object([]) do |token, locals|
        (lineno, column), type, value, = token
        column += parent_column if lineno == 1
        lineno += parent_line

        # Make the state transition for the parser. If there isn't a transition
        # from the current state to a new state for this type, then we're in a
        # pattern that isn't actually locals. In that case we can return [].
        state = transitions[state].fetch(type) { return [] }

        # If we hit an identifier, then add it to our list.
        next if type != :on_ident

        location =
          Location.token(
            line: lineno,
            char: line_counts[lineno - 1][column],
            column: column,
            size: value.size
          )

        locals << Ident.new(value: value, location: location)
      end
    end

    # :call-seq:
    #   on_lbrace: (String value) -> LBrace
    def on_lbrace(value)
      node =
        LBrace.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_lbracket: (String value) -> LBracket
    def on_lbracket(value)
      node =
        LBracket.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_lparen: (String value) -> LParen
    def on_lparen(value)
      node =
        LParen.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # def on_magic_comment(key, value)
    #   [key, value]
    # end

    # :call-seq:
    #   on_massign: ((MLHS | MLHSParen) target, untyped value) -> MAssign
    def on_massign(target, value)
      comma_range = target.location.end_char...value.location.start_char
      target.comma = true if source[comma_range].strip.start_with?(",")

      MAssign.new(
        target: target,
        value: value,
        location: target.location.to(value.location)
      )
    end

    # :call-seq:
    #   on_method_add_arg: (
    #     CallNode call,
    #     (ArgParen | Args) arguments
    #   ) -> CallNode
    def on_method_add_arg(call, arguments)
      location = call.location
      location = location.to(arguments.location) if arguments.is_a?(ArgParen)

      CallNode.new(
        receiver: call.receiver,
        operator: call.operator,
        message: call.message,
        arguments: arguments,
        location: location
      )
    end

    # :call-seq:
    #   on_method_add_block: (
    #     (Break | Call | Command | CommandCall, Next) call,
    #     Block block
    #   ) -> Break | MethodAddBlock
    def on_method_add_block(call, block)
      location = call.location.to(block.location)

      case call
      when Break, Next, ReturnNode
        parts = call.arguments.parts

        node = parts.pop
        copied =
          node.copy(block: block, location: node.location.to(block.location))

        copied.comments.concat(call.comments)
        parts << copied

        call.copy(location: location)
      when Command, CommandCall
        node = call.copy(block: block, location: location)
        node.comments.concat(call.comments)
        node
      else
        MethodAddBlock.new(call: call, block: block, location: location)
      end
    end

    # :call-seq:
    #   on_mlhs_add: (
    #     MLHS mlhs,
    #     (ARefField | Field | Ident | MLHSParen | VarField) part
    #   ) -> MLHS
    def on_mlhs_add(mlhs, part)
      location =
        mlhs.parts.empty? ? part.location : mlhs.location.to(part.location)

      MLHS.new(parts: mlhs.parts << part, location: location)
    end

    # :call-seq:
    #   on_mlhs_add_post: (MLHS left, MLHS right) -> MLHS
    def on_mlhs_add_post(left, right)
      MLHS.new(
        parts: left.parts + right.parts,
        location: left.location.to(right.location)
      )
    end

    # :call-seq:
    #   on_mlhs_add_star: (
    #     MLHS mlhs,
    #     (nil | ARefField | Field | Ident | VarField) part
    #   ) -> MLHS
    def on_mlhs_add_star(mlhs, part)
      beginning = consume_operator(:*)
      ending = part || beginning

      location = beginning.location.to(ending.location)
      arg_star = ArgStar.new(value: part, location: location)

      location = mlhs.location.to(location) unless mlhs.parts.empty?
      MLHS.new(parts: mlhs.parts << arg_star, location: location)
    end

    # :call-seq:
    #   on_mlhs_new: () -> MLHS
    def on_mlhs_new
      MLHS.new(
        parts: [],
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_mlhs_paren: ((MLHS | MLHSParen) contents) -> MLHSParen
    def on_mlhs_paren(contents)
      lparen = consume_token(LParen)
      rparen = consume_token(RParen)

      comma_range = lparen.location.end_char...rparen.location.start_char
      contents.comma = true if source[comma_range].strip.end_with?(",")

      MLHSParen.new(
        contents: contents,
        location: lparen.location.to(rparen.location)
      )
    end

    # :call-seq:
    #   on_module: (
    #     (ConstPathRef | ConstRef | TopConstRef) constant,
    #     BodyStmt bodystmt
    #   ) -> ModuleDeclaration
    def on_module(constant, bodystmt)
      beginning = consume_keyword(:module)
      ending = consume_keyword(:end)
      start_char = find_next_statement_start(constant.location.end_char)

      bodystmt.bind(
        self,
        start_char,
        start_char - line_counts[constant.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      ModuleDeclaration.new(
        constant: constant,
        bodystmt: bodystmt,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_mrhs_new: () -> MRHS
    def on_mrhs_new
      MRHS.new(
        parts: [],
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_mrhs_add: (MRHS mrhs, untyped part) -> MRHS
    def on_mrhs_add(mrhs, part)
      location =
        (mrhs.parts.empty? ? mrhs.location : mrhs.location.to(part.location))

      MRHS.new(parts: mrhs.parts << part, location: location)
    end

    # :call-seq:
    #   on_mrhs_add_star: (MRHS mrhs, untyped value) -> MRHS
    def on_mrhs_add_star(mrhs, value)
      beginning = consume_operator(:*)
      ending = value || beginning

      arg_star =
        ArgStar.new(
          value: value,
          location: beginning.location.to(ending.location)
        )

      location =
        if mrhs.parts.empty?
          arg_star.location
        else
          mrhs.location.to(arg_star.location)
        end

      MRHS.new(parts: mrhs.parts << arg_star, location: location)
    end

    # :call-seq:
    #   on_mrhs_new_from_args: (Args arguments) -> MRHS
    def on_mrhs_new_from_args(arguments)
      MRHS.new(parts: arguments.parts, location: arguments.location)
    end

    # :call-seq:
    #   on_next: (Args arguments) -> Next
    def on_next(arguments)
      keyword = consume_keyword(:next)

      location = keyword.location
      location = location.to(arguments.location) if arguments.parts.any?

      Next.new(arguments: arguments, location: location)
    end

    # def on_nl(value)
    #   value
    # end

    # def on_nokw_param(value)
    #   value
    # end

    # :call-seq:
    #   on_op: (String value) -> Op
    def on_op(value)
      node =
        Op.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_opassign: (
    #     (
    #       ARefField |
    #       ConstPathField |
    #       Field |
    #       TopConstField |
    #       VarField
    #     ) target,
    #     Op operator,
    #     untyped value
    #   ) -> OpAssign
    def on_opassign(target, operator, value)
      OpAssign.new(
        target: target,
        operator: operator,
        value: value,
        location: target.location.to(value.location)
      )
    end

    # def on_operator_ambiguous(value)
    #   value
    # end

    # :call-seq:
    #   on_params: (
    #     (nil | Array[Ident]) requireds,
    #     (nil | Array[[Ident, untyped]]) optionals,
    #     (nil | ArgsForward | ExcessedComma | RestParam) rest,
    #     (nil | Array[Ident]) posts,
    #     (nil | Array[[Ident, nil | untyped]]) keywords,
    #     (nil | :nil | ArgsForward | KwRestParam) keyword_rest,
    #     (nil | :& | BlockArg) block
    #   ) -> Params
    def on_params(
      requireds,
      optionals,
      rest,
      posts,
      keywords,
      keyword_rest,
      block
    )
      # This is to make it so that required keyword arguments
      # have a `nil` for the value instead of a `false`.
      keywords&.map! { |(key, value)| [key, value || nil] }

      # Here we're going to build up a list of all of the params so that we can
      # determine our location information.
      parts = []

      requireds&.each { |required| parts << required.location }
      optionals&.each do |(key, value)|
        parts << key.location
        parts << value.location if value
      end

      parts << rest.location if rest
      posts&.each { |post| parts << post.location }

      keywords&.each do |(key, value)|
        parts << key.location
        parts << value.location if value
      end

      if keyword_rest == :nil
        # When we get a :nil here, it means that we have **nil syntax, which
        # means this set of parameters accepts no more keyword arguments. In
        # this case we need to go and find the location of these two tokens.
        operator = consume_operator(:**)
        parts << operator.location.to(consume_keyword(:nil).location)
      elsif keyword_rest
        parts << keyword_rest.location
      end

      parts << block.location if block && block != :&
      parts = parts.compact

      location =
        if parts.any?
          parts[0].to(parts[-1])
        else
          Location.fixed(line: lineno, char: char_pos, column: current_column)
        end

      Params.new(
        requireds: requireds || [],
        optionals: optionals || [],
        rest: rest,
        posts: posts || [],
        keywords: keywords || [],
        keyword_rest: keyword_rest,
        block: (block if block != :&),
        location: location
      )
    end

    # :call-seq:
    #   on_paren: (untyped contents) -> Paren
    def on_paren(contents)
      lparen = consume_token(LParen)
      rparen = consume_token(RParen)

      if contents.is_a?(Params)
        location = contents.location
        start_char = find_next_statement_start(lparen.location.end_char)
        location =
          Location.new(
            start_line: location.start_line,
            start_char: start_char,
            start_column:
              start_char - line_counts[lparen.location.start_line - 1].start,
            end_line: location.end_line,
            end_char: rparen.location.start_char,
            end_column: rparen.location.start_column
          )

        contents =
          Params.new(
            requireds: contents.requireds,
            optionals: contents.optionals,
            rest: contents.rest,
            posts: contents.posts,
            keywords: contents.keywords,
            keyword_rest: contents.keyword_rest,
            block: contents.block,
            location: location
          )
      end

      Paren.new(
        lparen: lparen,
        contents: contents || nil,
        location: lparen.location.to(rparen.location)
      )
    end

    # If we encounter a parse error, just immediately bail out so that our
    # runner can catch it.
    def on_parse_error(error, *)
      raise ParseError.new(error, lineno, column)
    end
    alias on_alias_error on_parse_error
    alias on_assign_error on_parse_error
    alias on_class_name_error on_parse_error
    alias on_param_error on_parse_error

    # :call-seq:
    #   on_period: (String value) -> Period
    def on_period(value)
      Period.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_program: (Statements statements) -> Program
    def on_program(statements)
      last_column = source.length - line_counts.last.start
      location =
        Location.new(
          start_line: 1,
          start_char: 0,
          start_column: 0,
          end_line: line_counts.length - 1,
          end_char: source.length,
          end_column: last_column
        )

      statements.body << @__end__ if @__end__
      statements.bind(self, 0, 0, source.length, last_column)

      program = Program.new(statements: statements, location: location)
      attach_comments(program, @comments)

      program
    end

    # Attaches comments to the nodes in the tree that most closely correspond to
    # the location of the comments.
    def attach_comments(program, comments)
      comments.each do |comment|
        preceding, enclosing, following = nearest_nodes(program, comment)

        if comment.inline?
          if preceding
            preceding.comments << comment
            comment.trailing!
          elsif following
            following.comments << comment
            comment.leading!
          elsif enclosing
            enclosing.comments << comment
          else
            program.comments << comment
          end
        else
          # If a comment exists on its own line, prefer a leading comment.
          if following
            following.comments << comment
            comment.leading!
          elsif preceding
            preceding.comments << comment
            comment.trailing!
          elsif enclosing
            enclosing.comments << comment
          else
            program.comments << comment
          end
        end
      end
    end

    # Responsible for finding the nearest nodes to the given comment within the
    # context of the given encapsulating node.
    def nearest_nodes(node, comment)
      comment_start = comment.location.start_char
      comment_end = comment.location.end_char

      child_nodes = node.child_nodes.compact
      preceding = nil
      following = nil

      left = 0
      right = child_nodes.length

      # This is a custom binary search that finds the nearest nodes to the given
      # comment. When it finds a node that completely encapsulates the comment,
      # it recursed downward into the tree.
      while left < right
        middle = (left + right) / 2
        child = child_nodes[middle]

        node_start = child.location.start_char
        node_end = child.location.end_char

        if node_start <= comment_start && comment_end <= node_end
          # The comment is completely contained by this child node. Abandon the
          # binary search at this level.
          return nearest_nodes(child, comment)
        end

        if node_end <= comment_start
          # This child node falls completely before the comment. Because we will
          # never consider this node or any nodes before it again, this node
          # must be the closest preceding node we have encountered so far.
          preceding = child
          left = middle + 1
          next
        end

        if comment_end <= node_start
          # This child node falls completely after the comment. Because we will
          # never consider this node or any nodes after it again, this node must
          # be the closest following node we have encountered so far.
          following = child
          right = middle
          next
        end

        # This should only happen if there is a bug in this parser.
        raise "Comment location overlaps with node location"
      end

      [preceding, node, following]
    end

    # :call-seq:
    #   on_qsymbols_add: (QSymbols qsymbols, TStringContent element) -> QSymbols
    def on_qsymbols_add(qsymbols, element)
      QSymbols.new(
        beginning: qsymbols.beginning,
        elements: qsymbols.elements << element,
        location: qsymbols.location.to(element.location)
      )
    end

    # :call-seq:
    #   on_qsymbols_beg: (String value) -> QSymbolsBeg
    def on_qsymbols_beg(value)
      node =
        QSymbolsBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_qsymbols_new: () -> QSymbols
    def on_qsymbols_new
      beginning = consume_token(QSymbolsBeg)

      QSymbols.new(
        beginning: beginning,
        elements: [],
        location: beginning.location
      )
    end

    # :call-seq:
    #   on_qwords_add: (QWords qwords, TStringContent element) -> QWords
    def on_qwords_add(qwords, element)
      QWords.new(
        beginning: qwords.beginning,
        elements: qwords.elements << element,
        location: qwords.location.to(element.location)
      )
    end

    # :call-seq:
    #   on_qwords_beg: (String value) -> QWordsBeg
    def on_qwords_beg(value)
      node =
        QWordsBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_qwords_new: () -> QWords
    def on_qwords_new
      beginning = consume_token(QWordsBeg)

      QWords.new(
        beginning: beginning,
        elements: [],
        location: beginning.location
      )
    end

    # :call-seq:
    #   on_rational: (String value) -> RationalLiteral
    def on_rational(value)
      RationalLiteral.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_rbrace: (String value) -> RBrace
    def on_rbrace(value)
      node =
        RBrace.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_rbracket: (String value) -> RBracket
    def on_rbracket(value)
      node =
        RBracket.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_redo: () -> Redo
    def on_redo
      keyword = consume_keyword(:redo)

      Redo.new(location: keyword.location)
    end

    # :call-seq:
    #   on_regexp_add: (
    #     RegexpContent regexp_content,
    #     (StringDVar | StringEmbExpr | TStringContent) part
    #   ) -> RegexpContent
    def on_regexp_add(regexp_content, part)
      RegexpContent.new(
        beginning: regexp_content.beginning,
        parts: regexp_content.parts << part,
        location: regexp_content.location.to(part.location)
      )
    end

    # :call-seq:
    #   on_regexp_beg: (String value) -> RegexpBeg
    def on_regexp_beg(value)
      node =
        RegexpBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_regexp_end: (String value) -> RegexpEnd
    def on_regexp_end(value)
      RegexpEnd.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_regexp_literal: (
    #     RegexpContent regexp_content,
    #     (nil | RegexpEnd) ending
    #   ) -> RegexpLiteral
    def on_regexp_literal(regexp_content, ending)
      location = regexp_content.location

      if ending.nil?
        message = "Cannot find expected regular expression ending"
        raise ParseError.new(message, *find_token_error(location))
      end

      RegexpLiteral.new(
        beginning: regexp_content.beginning,
        ending: ending.value,
        parts: regexp_content.parts,
        location: location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_regexp_new: () -> RegexpContent
    def on_regexp_new
      regexp_beg = consume_token(RegexpBeg)

      RegexpContent.new(
        beginning: regexp_beg.value,
        parts: [],
        location: regexp_beg.location
      )
    end

    # :call-seq:
    #   on_rescue: (
    #     (nil | [untyped] | MRHS | MRHSAddStar) exceptions,
    #     (nil | Field | VarField) variable,
    #     Statements statements,
    #     (nil | Rescue) consequent
    #   ) -> Rescue
    def on_rescue(exceptions, variable, statements, consequent)
      keyword = consume_keyword(:rescue)
      exceptions = exceptions[0] if exceptions.is_a?(Array)

      last_node = variable || exceptions || keyword
      start_char = find_next_statement_start(last_node.end_char)
      statements.bind(
        self,
        start_char,
        start_char - line_counts[last_node.location.start_line - 1].start,
        char_pos,
        current_column
      )

      # We add an additional inner node here that ripper doesn't provide so that
      # we have a nice place to attach inline comments. But we only need it if
      # we have an exception or a variable that we're rescuing.
      rescue_ex =
        if exceptions || variable
          RescueEx.new(
            exceptions: exceptions,
            variable: variable,
            location:
              Location.new(
                start_line: keyword.location.start_line,
                start_char: keyword.location.end_char + 1,
                start_column: keyword.location.end_column + 1,
                end_line: last_node.location.end_line,
                end_char: last_node.end_char,
                end_column: last_node.location.end_column
              )
          )
        end

      Rescue.new(
        keyword: keyword,
        exception: rescue_ex,
        statements: statements,
        consequent: consequent,
        location:
          Location.new(
            start_line: keyword.location.start_line,
            start_char: keyword.location.start_char,
            start_column: keyword.location.start_column,
            end_line: lineno,
            end_char: char_pos,
            end_column: current_column
          )
      )
    end

    # :call-seq:
    #   on_rescue_mod: (untyped statement, untyped value) -> RescueMod
    def on_rescue_mod(statement, value)
      consume_keyword(:rescue)

      RescueMod.new(
        statement: statement,
        value: value,
        location: statement.location.to(value.location)
      )
    end

    # :call-seq:
    #   on_rest_param: ((nil | Ident) name) -> RestParam
    def on_rest_param(name)
      location = consume_operator(:*).location
      location = location.to(name.location) if name

      RestParam.new(name: name, location: location)
    end

    # :call-seq:
    #   on_retry: () -> Retry
    def on_retry
      keyword = consume_keyword(:retry)

      Retry.new(location: keyword.location)
    end

    # :call-seq:
    #   on_return: (Args arguments) -> ReturnNode
    def on_return(arguments)
      keyword = consume_keyword(:return)

      ReturnNode.new(
        arguments: arguments,
        location: keyword.location.to(arguments.location)
      )
    end

    # :call-seq:
    #   on_return0: () -> ReturnNode
    def on_return0
      keyword = consume_keyword(:return)

      ReturnNode.new(arguments: nil, location: keyword.location)
    end

    # :call-seq:
    #   on_rparen: (String value) -> RParen
    def on_rparen(value)
      node =
        RParen.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_sclass: (untyped target, BodyStmt bodystmt) -> SClass
    def on_sclass(target, bodystmt)
      beginning = consume_keyword(:class)
      ending = consume_keyword(:end)
      start_char = find_next_statement_start(target.location.end_char)

      bodystmt.bind(
        self,
        start_char,
        start_char - line_counts[target.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      SClass.new(
        target: target,
        bodystmt: bodystmt,
        location: beginning.location.to(ending.location)
      )
    end

    # Semicolons are tokens that get added to the token list but never get
    # attached to the AST. Because of this they only need to track their
    # associated location so they can be used for computing bounds.
    class Semicolon
      attr_reader :location

      def initialize(location)
        @location = location
      end
    end

    # :call-seq:
    #   on_semicolon: (String value) -> Semicolon
    def on_semicolon(value)
      tokens << Semicolon.new(
        Location.token(
          line: lineno,
          char: char_pos,
          column: current_column,
          size: value.size
        )
      )
    end

    # def on_sp(value)
    #   value
    # end

    # stmts_add is a parser event that represents a single statement inside a
    # list of statements within any lexical block. It accepts as arguments the
    # parent stmts node as well as an stmt which can be any expression in
    # Ruby.
    def on_stmts_add(statements, statement)
      location =
        if statements.body.empty?
          statement.location
        else
          statements.location.to(statement.location)
        end

      Statements.new(body: statements.body << statement, location: location)
    end

    # :call-seq:
    #   on_stmts_new: () -> Statements
    def on_stmts_new
      Statements.new(
        body: [],
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_string_add: (
    #     String string,
    #     (StringEmbExpr | StringDVar | TStringContent) part
    #   ) -> StringContent
    def on_string_add(string, part)
      # Due to some eccentricities in how ripper works, you need this here in
      # case you have a syntax error with an embedded expression that doesn't
      # finish, as in: "#{"
      return string if part.is_a?(String)

      location =
        string.parts.any? ? string.location.to(part.location) : part.location

      StringContent.new(parts: string.parts << part, location: location)
    end

    # :call-seq:
    #   on_string_concat: (
    #     (StringConcat | StringLiteral) left,
    #     StringLiteral right
    #   ) -> StringConcat
    def on_string_concat(left, right)
      StringConcat.new(
        left: left,
        right: right,
        location: left.location.to(right.location)
      )
    end

    # :call-seq:
    #   on_string_content: () -> StringContent
    def on_string_content
      StringContent.new(
        parts: [],
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_string_dvar: ((Backref | VarRef) variable) -> StringDVar
    def on_string_dvar(variable)
      embvar = consume_token(EmbVar)

      StringDVar.new(
        variable: variable,
        location: embvar.location.to(variable.location)
      )
    end

    # :call-seq:
    #   on_string_embexpr: (Statements statements) -> StringEmbExpr
    def on_string_embexpr(statements)
      embexpr_beg = consume_token(EmbExprBeg)
      embexpr_end = consume_token(EmbExprEnd)

      statements.bind(
        self,
        embexpr_beg.location.end_char,
        embexpr_beg.location.end_column,
        embexpr_end.location.start_char,
        embexpr_end.location.start_column
      )

      location =
        Location.new(
          start_line: embexpr_beg.location.start_line,
          start_char: embexpr_beg.location.start_char,
          start_column: embexpr_beg.location.start_column,
          end_line: [
            embexpr_end.location.end_line,
            statements.location.end_line
          ].max,
          end_char: embexpr_end.location.end_char,
          end_column: embexpr_end.location.end_column
        )

      StringEmbExpr.new(statements: statements, location: location)
    end

    # :call-seq:
    #   on_string_literal: (String string) -> Heredoc | StringLiteral
    def on_string_literal(string)
      heredoc = @heredocs[-1]

      if heredoc&.ending
        heredoc = @heredocs.pop

        Heredoc.new(
          beginning: heredoc.beginning,
          ending: heredoc.ending,
          dedent: heredoc.dedent,
          parts: string.parts,
          location: heredoc.location
        )
      else
        tstring_beg = consume_token(TStringBeg)
        tstring_end = consume_tstring_end(tstring_beg.location)

        location =
          Location.new(
            start_line: tstring_beg.location.start_line,
            start_char: tstring_beg.location.start_char,
            start_column: tstring_beg.location.start_column,
            end_line: [
              tstring_end.location.end_line,
              string.location.end_line
            ].max,
            end_char: tstring_end.location.end_char,
            end_column: tstring_end.location.end_column
          )

        StringLiteral.new(
          parts: string.parts,
          quote: tstring_beg.value,
          location: location
        )
      end
    end

    # :call-seq:
    #   on_super: ((ArgParen | Args) arguments) -> Super
    def on_super(arguments)
      keyword = consume_keyword(:super)

      Super.new(
        arguments: arguments,
        location: keyword.location.to(arguments.location)
      )
    end

    # symbeg is a token that represents the beginning of a symbol literal. In
    # most cases it will contain just ":" as in the value, but if its a dynamic
    # symbol being defined it will contain ":'" or ":\"".
    def on_symbeg(value)
      node =
        SymBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_symbol: (
    #     (Backtick | Const | CVar | GVar | Ident | IVar | Kw | Op) value
    #   ) -> SymbolContent
    def on_symbol(value)
      tokens.delete(value)

      SymbolContent.new(value: value, location: value.location)
    end

    # :call-seq:
    #   on_symbol_literal: (
    #     (
    #       Backtick | Const | CVar | GVar | Ident |
    #       IVar | Kw | Op | SymbolContent
    #     ) value
    #   ) -> SymbolLiteral
    def on_symbol_literal(value)
      if value.is_a?(SymbolContent)
        symbeg = consume_token(SymBeg)

        SymbolLiteral.new(
          value: value.value,
          location: symbeg.location.to(value.location)
        )
      else
        tokens.delete(value)
        SymbolLiteral.new(value: value, location: value.location)
      end
    end

    # :call-seq:
    #   on_symbols_add: (Symbols symbols, Word word) -> Symbols
    def on_symbols_add(symbols, word)
      Symbols.new(
        beginning: symbols.beginning,
        elements: symbols.elements << word,
        location: symbols.location.to(word.location)
      )
    end

    # :call-seq:
    #   on_symbols_beg: (String value) -> SymbolsBeg
    def on_symbols_beg(value)
      node =
        SymbolsBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_symbols_new: () -> Symbols
    def on_symbols_new
      beginning = consume_token(SymbolsBeg)

      Symbols.new(
        beginning: beginning,
        elements: [],
        location: beginning.location
      )
    end

    # :call-seq:
    #   on_tlambda: (String value) -> TLambda
    def on_tlambda(value)
      node =
        TLambda.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_tlambeg: (String value) -> TLamBeg
    def on_tlambeg(value)
      node =
        TLamBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_top_const_field: (Const constant) -> TopConstRef
    def on_top_const_field(constant)
      operator = find_colon2_before(constant)

      TopConstField.new(
        constant: constant,
        location: operator.location.to(constant.location)
      )
    end

    # :call-seq:
    #   on_top_const_ref: (Const constant) -> TopConstRef
    def on_top_const_ref(constant)
      operator = find_colon2_before(constant)

      TopConstRef.new(
        constant: constant,
        location: operator.location.to(constant.location)
      )
    end

    # :call-seq:
    #   on_tstring_beg: (String value) -> TStringBeg
    def on_tstring_beg(value)
      node =
        TStringBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_tstring_content: (String value) -> TStringContent
    def on_tstring_content(value)
      TStringContent.new(
        value: value,
        location:
          Location.token(
            line: lineno,
            char: char_pos,
            column: current_column,
            size: value.size
          )
      )
    end

    # :call-seq:
    #   on_tstring_end: (String value) -> TStringEnd
    def on_tstring_end(value)
      node =
        TStringEnd.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_unary: (:not operator, untyped statement) -> Not
    #           | (Symbol operator, untyped statement) -> Unary
    def on_unary(operator, statement)
      if operator == :not
        # We have somewhat special handling of the not operator since if it has
        # parentheses they don't get reported as a paren node for some reason.

        beginning = consume_keyword(:not)
        ending = statement || beginning
        parentheses = source[beginning.location.end_char] == "("

        if parentheses
          consume_token(LParen)
          ending = consume_token(RParen)
        end

        Not.new(
          statement: statement,
          parentheses: parentheses,
          location: beginning.location.to(ending.location)
        )
      else
        # Special case instead of using find_token here. It turns out that
        # if you have a range that goes from a negative number to a negative
        # number then you can end up with a .. or a ... that's higher in the
        # stack. So we need to explicitly disallow those operators.
        index =
          tokens.rindex do |token|
            token.is_a?(Op) &&
              token.location.start_char < statement.location.start_char &&
              !%w[.. ...].include?(token.value)
          end

        beginning = tokens.delete_at(index)

        Unary.new(
          operator: operator[0], # :+@ -> "+"
          statement: statement,
          location: beginning.location.to(statement.location)
        )
      end
    end

    # :call-seq:
    #   on_undef: (Array[DynaSymbol | SymbolLiteral] symbols) -> Undef
    def on_undef(symbols)
      keyword = consume_keyword(:undef)

      Undef.new(
        symbols: symbols,
        location: keyword.location.to(symbols.last.location)
      )
    end

    # :call-seq:
    #   on_unless: (
    #     untyped predicate,
    #     Statements statements,
    #     ((nil | Elsif | Else) consequent)
    #   ) -> UnlessNode
    def on_unless(predicate, statements, consequent)
      beginning = consume_keyword(:unless)
      ending = consequent || consume_keyword(:end)

      if (keyword = find_keyword_between(:then, predicate, ending))
        tokens.delete(keyword)
      end

      start_char =
        find_next_statement_start((keyword || predicate).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char - line_counts[predicate.location.end_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      UnlessNode.new(
        predicate: predicate,
        statements: statements,
        consequent: consequent,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_unless_mod: (untyped predicate, untyped statement) -> UnlessNode
    def on_unless_mod(predicate, statement)
      consume_keyword(:unless)

      UnlessNode.new(
        predicate: predicate,
        statements:
          Statements.new(body: [statement], location: statement.location),
        consequent: nil,
        location: statement.location.to(predicate.location)
      )
    end

    # :call-seq:
    #   on_until: (untyped predicate, Statements statements) -> UntilNode
    def on_until(predicate, statements)
      beginning = consume_keyword(:until)
      ending = consume_keyword(:end)

      delimiter =
        find_keyword_between(:do, predicate, statements) ||
          find_token_between(Semicolon, predicate, statements)

      tokens.delete(delimiter) if delimiter

      # Update the Statements location information
      start_char =
        find_next_statement_start((delimiter || predicate).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char - line_counts[predicate.location.end_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      UntilNode.new(
        predicate: predicate,
        statements: statements,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_until_mod: (untyped predicate, untyped statement) -> UntilNode
    def on_until_mod(predicate, statement)
      consume_keyword(:until)

      UntilNode.new(
        predicate: predicate,
        statements:
          Statements.new(body: [statement], location: statement.location),
        location: statement.location.to(predicate.location)
      )
    end

    # :call-seq:
    #   on_var_alias: (GVar left, (Backref | GVar) right) -> AliasNode
    def on_var_alias(left, right)
      keyword = consume_keyword(:alias)

      AliasNode.new(
        left: left,
        right: right,
        location: keyword.location.to(right.location)
      )
    end

    # :call-seq:
    #   on_var_field: (
    #     (nil | Const | CVar | GVar | Ident | IVar) value
    #   ) -> VarField
    def on_var_field(value)
      location =
        if value && value != :nil
          value.location
        else
          # You can hit this pattern if you're assigning to a splat using
          # pattern matching syntax in Ruby 2.7+
          Location.fixed(line: lineno, char: char_pos, column: current_column)
        end

      VarField.new(value: value, location: location)
    end

    # :call-seq:
    #   on_var_ref: ((Const | CVar | GVar | Ident | IVar | Kw) value) -> VarRef
    def on_var_ref(value)
      VarRef.new(value: value, location: value.location)
    end

    # :call-seq:
    #   on_vcall: (Ident ident) -> VCall
    def on_vcall(ident)
      VCall.new(value: ident, location: ident.location)
    end

    # :call-seq:
    #   on_void_stmt: () -> VoidStmt
    def on_void_stmt
      VoidStmt.new(
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_when: (
    #     Args arguments,
    #     Statements statements,
    #     (nil | Else | When) consequent
    #   ) -> When
    def on_when(arguments, statements, consequent)
      beginning = consume_keyword(:when)
      ending = consequent || consume_keyword(:end)

      statements_start = arguments
      if (token = find_keyword(:then))
        tokens.delete(token)
        statements_start = token
      end

      start_char =
        find_next_statement_start((token || statements_start).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char -
          line_counts[statements_start.location.start_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      When.new(
        arguments: arguments,
        statements: statements,
        consequent: consequent,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_while: (untyped predicate, Statements statements) -> WhileNode
    def on_while(predicate, statements)
      beginning = consume_keyword(:while)
      ending = consume_keyword(:end)

      delimiter =
        find_keyword_between(:do, predicate, statements) ||
          find_token_between(Semicolon, predicate, statements)

      tokens.delete(delimiter) if delimiter

      # Update the Statements location information
      start_char =
        find_next_statement_start((delimiter || predicate).location.end_char)

      statements.bind(
        self,
        start_char,
        start_char - line_counts[predicate.location.end_line - 1].start,
        ending.location.start_char,
        ending.location.start_column
      )

      WhileNode.new(
        predicate: predicate,
        statements: statements,
        location: beginning.location.to(ending.location)
      )
    end

    # :call-seq:
    #   on_while_mod: (untyped predicate, untyped statement) -> WhileNode
    def on_while_mod(predicate, statement)
      consume_keyword(:while)

      WhileNode.new(
        predicate: predicate,
        statements:
          Statements.new(body: [statement], location: statement.location),
        location: statement.location.to(predicate.location)
      )
    end

    # :call-seq:
    #   on_word_add: (
    #     Word word,
    #     (StringEmbExpr | StringDVar | TStringContent) part
    #   ) -> Word
    def on_word_add(word, part)
      location =
        word.parts.empty? ? part.location : word.location.to(part.location)

      Word.new(parts: word.parts << part, location: location)
    end

    # :call-seq:
    #   on_word_new: () -> Word
    def on_word_new
      Word.new(
        parts: [],
        location:
          Location.fixed(line: lineno, char: char_pos, column: current_column)
      )
    end

    # :call-seq:
    #   on_words_add: (Words words, Word word) -> Words
    def on_words_add(words, word)
      Words.new(
        beginning: words.beginning,
        elements: words.elements << word,
        location: words.location.to(word.location)
      )
    end

    # :call-seq:
    #   on_words_beg: (String value) -> WordsBeg
    def on_words_beg(value)
      node =
        WordsBeg.new(
          value: value,
          location:
            Location.token(
              line: lineno,
              char: char_pos,
              column: current_column,
              size: value.size
            )
        )

      tokens << node
      node
    end

    # :call-seq:
    #   on_words_new: () -> Words
    def on_words_new
      beginning = consume_token(WordsBeg)

      Words.new(
        beginning: beginning,
        elements: [],
        location: beginning.location
      )
    end

    # def on_words_sep(value)
    #   value
    # end

    # :call-seq:
    #   on_xstring_add: (
    #     XString xstring,
    #     (StringEmbExpr | StringDVar | TStringContent) part
    #   ) -> XString
    def on_xstring_add(xstring, part)
      XString.new(
        parts: xstring.parts << part,
        location: xstring.location.to(part.location)
      )
    end

    # :call-seq:
    #   on_xstring_new: () -> XString
    def on_xstring_new
      heredoc = @heredocs[-1]

      location =
        if heredoc && heredoc.beginning.value.include?("`")
          heredoc.location
        else
          consume_token(Backtick).location
        end

      XString.new(parts: [], location: location)
    end

    # :call-seq:
    #   on_xstring_literal: (XString xstring) -> Heredoc | XStringLiteral
    def on_xstring_literal(xstring)
      heredoc = @heredocs[-1]

      if heredoc && heredoc.beginning.value.include?("`")
        Heredoc.new(
          beginning: heredoc.beginning,
          ending: heredoc.ending,
          dedent: heredoc.dedent,
          parts: xstring.parts,
          location: heredoc.location
        )
      else
        ending = consume_tstring_end(xstring.location)

        XStringLiteral.new(
          parts: xstring.parts,
          location: xstring.location.to(ending.location)
        )
      end
    end

    # :call-seq:
    #   on_yield: ((Args | Paren) arguments) -> YieldNode
    def on_yield(arguments)
      keyword = consume_keyword(:yield)

      YieldNode.new(
        arguments: arguments,
        location: keyword.location.to(arguments.location)
      )
    end

    # :call-seq:
    #   on_yield0: () -> YieldNode
    def on_yield0
      keyword = consume_keyword(:yield)

      YieldNode.new(arguments: nil, location: keyword.location)
    end

    # :call-seq:
    #   on_zsuper: () -> ZSuper
    def on_zsuper
      keyword = consume_keyword(:super)

      ZSuper.new(location: keyword.location)
    end
  end
end
