# frozen_string_literal: true

module SyntaxTree
  # A slightly enhanced PP that knows how to format recursively including
  # comments.
  class Formatter < PP
    COMMENT_PRIORITY = 1
    HEREDOC_PRIORITY = 2

    attr_reader :source, :stack, :quote

    def initialize(source, ...)
      super(...)

      @source = source
      @stack = []
      @quote = "\""
    end

    def format(node, stackable: true)
      stack << node if stackable
      doc = nil

      # If there are comments, then we're going to format them around the node
      # so that they get printed properly.
      if node.comments.any?
        leading, trailing = node.comments.partition(&:leading?)

        # Print all comments that were found before the node.
        leading.each do |comment|
          comment.format(self)
          breakable(force: true)
        end

        # If the node has a stree-ignore comment right before it, then we're
        # going to just print out the node as it was seen in the source.
        if leading.last&.ignore?
          doc = text(source[node.location.start_char...node.location.end_char])
        else
          doc = node.format(self)
        end

        # Print all comments that were found after the node.
        trailing.each do |comment|
          line_suffix(priority: COMMENT_PRIORITY) do
            text(" ")
            comment.format(self)
            break_parent
          end
        end
      else
        doc = node.format(self)
      end

      stack.pop if stackable
      doc
    end

    def format_each(nodes)
      nodes.each { |node| format(node) }
    end

    def parent
      stack[-2]
    end

    def parents
      stack[0...-1].reverse_each
    end
  end

  # Formatters

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

  class AryPtnRestFormatter
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
      # If the predicate of the conditional contains an assignment (in which
      # case we can't know for certain that that assignment doesn't impact the
      # statements inside the conditional) then we can't use the modifier form
      # and we must use the block form.
      if ContainsAssignment.call(node.predicate)
        format_break(q, force: true)
        return
      end

      if node.consequent || node.statements.empty?
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

  # Formats either a Break or Next node.
  class FlowControlFormatter
    # [String] the keyword to print
    attr_reader :keyword

    # [Break | Next] the node being formatted
    attr_reader :node

    def initialize(keyword, node)
      @keyword = keyword
      @node = node
    end

    def format(q)
      arguments = node.arguments

      q.group do
        q.text(keyword)

        if arguments.parts.any?
          if arguments.parts.length == 1
            part = arguments.parts.first

            if part.is_a?(Paren)
              q.format(arguments)
            elsif part.is_a?(ArrayLiteral)
              q.text(" ")
              q.format(arguments)
            else
              format_arguments(q, "(", ")")
            end
          else
            format_arguments(q, " [", "]")
          end
        end
      end
    end

    private

    def format_arguments(q, opening, closing)
      q.if_break { q.text(opening) }
      q.indent do
        q.breakable(" ")
        q.format(node.arguments)
      end
      q.breakable("")
      q.if_break { q.text(closing) }
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

  class HshPtnKeywordFormatter
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

  class HshPtnKeywordRestFormatter
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

  class ParamsKeywordFormatter
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

  class ParamsKeywordRestFormatter
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

  class ParamsOptionalFormatter
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
end
