# frozen_string_literal: true

require "prism"

module Prism
  class Node
    def heredoc_end_line
      @heredoc_end_line ||= [end_line, *compact_child_nodes.map(&:heredoc_end_line)].max
    end
  end

  class StringNode < Node
    def heredoc_end_line
      @heredoc_end_line ||= (heredoc? ? closing_loc.start_line : end_line)
    end
  end

  class XStringNode < Node
    def heredoc_end_line
      @heredoc_end_line ||= (heredoc? ? closing_loc.start_line : end_line)
    end
  end

  class InterpolatedStringNode < Node
    def heredoc_end_line
      @heredoc_end_line ||= [
        heredoc? ? closing_loc.start_line : end_line,
        *compact_child_nodes.map(&:heredoc_end_line)
      ].max
    end
  end

  class InterpolatedXStringNode < Node
    def heredoc_end_line
      @heredoc_end_line ||= [
        heredoc? ? closing_loc.start_line : end_line,
        *compact_child_nodes.map(&:heredoc_end_line)
      ].max
    end
  end

  # Philip Wadler, A prettier printer, March 1998
  # https://homepages.inf.ed.ac.uk/wadler/papers/prettier/prettier.pdf
  class Format
    # A node in the print tree that represents aligning nested nodes to a
    # certain prefix width or string.
    class Align
      attr_reader :indent, :contents

      def initialize(indent, contents)
        @indent = indent
        @contents = contents
      end

      def type
        :align
      end
    end

    # A node in the print tree that represents a place in the buffer that the
    # content can be broken onto multiple lines.
    class Breakable
      attr_reader :separator, :width, :force, :indent

      def initialize(separator, width, force, indent)
        @separator = separator
        @width = width
        @force = force
        @indent = indent
      end

      def type
        :breakable
      end
    end

    # Below here are the most common combination of options that are created
    # when creating new breakables. They are here to cut down on some
    # allocations.
    BREAKABLE_SPACE = Breakable.new(" ", 1, false, true).freeze
    BREAKABLE_EMPTY = Breakable.new("", 0, false, true).freeze
    BREAKABLE_FORCE = Breakable.new(" ", 1, true, true).freeze
    BREAKABLE_RETURN = Breakable.new(" ", 1, true, false).freeze

    # A node in the print tree that forces the surrounding group to print out in
    # the "break" mode as opposed to the "flat" mode. Useful for when you need
    # to force a newline into a group.
    class BreakParent
      def type
        :break_parent
      end
    end

    # Since there's really no difference in these instances, just using the same
    # one saves on some allocations.
    BREAK_PARENT = BreakParent.new.freeze

    # A node in the print tree that represents a group of items which the printer
    # should try to fit onto one line. This is the basic command to tell the
    # printer when to break. Groups are usually nested, and the printer will try
    # to fit everything on one line, but if it doesn't fit it will break the
    # outermost group first and try again. It will continue breaking groups until
    # everything fits (or there are no more groups to break).
    class Group
      attr_reader :contents, :break

      def initialize(contents)
        @contents = contents
        @break = false
      end

      def unbreak!
        @break = false
      end

      def break!
        @break = true
      end

      def type
        :group
      end
    end

    # A node in the print tree that represents printing one thing if the
    # surrounding group node is broken and another thing if the surrounding group
    # node is flat.
    class IfBreak
      attr_reader :break_contents, :flat_contents

      def initialize(break_contents, flat_contents)
        @break_contents = break_contents
        @flat_contents = flat_contents
      end

      def type
        :if_break
      end
    end

    # A node in the print tree that is a variant of the Align node that indents
    # its contents by one level.
    class Indent
      attr_reader :contents

      def initialize(contents)
        @contents = contents
      end

      def type
        :indent
      end
    end

    # A node in the print tree that has its own special buffer for implementing
    # content that should flush before any newline.
    #
    # Useful for implementating trailing content, as it's not always practical to
    # constantly check where the line ends to avoid accidentally printing some
    # content after a line suffix node.
    class LineSuffix
      attr_reader :priority, :contents

      def initialize(priority, contents)
        @priority = priority
        @contents = contents
      end

      def type
        :line_suffix
      end
    end

    # A node in the print tree that represents trimming all of the indentation of
    # the current line, in the rare case that you need to ignore the indentation
    # that you've already created. This node should be placed after a Breakable.
    class Trim
      def type
        :trim
      end
    end

    # Since all of the instances here are the same, we can reuse the same one to
    # cut down on allocations.
    TRIM = Trim.new.freeze

    # Refine string so that we can consistently call #type in case statements and
    # treat all of the nodes in the tree as homogenous.
    using Module.new {
            refine String do
              def type
                :string
              end
            end
          }

    # There are two modes in printing, break and flat. When we're in break mode,
    # any lines will use their newline, any if-breaks will use their break
    # contents, etc.
    MODE_BREAK = 1

    # This is another print mode much like MODE_BREAK. When we're in flat mode, we
    # attempt to print everything on one line until we either hit a broken group,
    # a forced line, or the maximum width.
    MODE_FLAT = 2

    # The default indentation for printing is zero, assuming that the code starts
    # at the top level. That can be changed if desired to start from a different
    # indentation level.
    DEFAULT_INDENTATION = 0

    COMMENT_PRIORITY = 1
    HEREDOC_PRIORITY = 2

    attr_reader :source, :stack
    attr_reader :print_width, :preferred_quote, :trailing_comma

    # This is an output buffer that contains the various parts of the printed
    # source code.
    attr_reader :buffer

    # The stack of groups that are being printed.
    attr_reader :groups

    # The current array of contents that calls to methods that generate print
    # tree nodes will append to.
    attr_reader :target

    def initialize(source, options)
      @source = source
      @stack = []
      @buffer = []

      @print_width = options.print_width
      @preferred_quote = options.preferred_quote
      @trailing_comma = options.trailing_comma

      contents = []
      @groups = [Group.new(contents)]
      @target = contents
    end

    # The main API for this visitor.
    def format
      flush
      buffer.join
    end

    # A convenience method used by a lot of the print tree node builders that
    # temporarily changes the target that the builders will append to.
    def with_target(target)
      previous_target, @target = @target, target
      yield
      @target = previous_target
    end

    # --------------------------------------------------------------------------
    # Visit methods
    # --------------------------------------------------------------------------

    # alias $foo $bar
    # ^^^^^^^^^^^^^^^
    def visit_alias_global_variable_node(node)
      group do
        text("alias ")
        visit(node.new_name)
        align(6) do
          breakable_space
          visit(node.old_name)
        end
      end
    end

    # alias foo bar
    # ^^^^^^^^^^^^^
    def visit_alias_method_node(node)
      new_name = node.new_name
      old_name = node.old_name

      group do
        text("alias ")

        if new_name.is_a?(SymbolNode)
          text(new_name.value)
          new_name.location.comments.each { |comment| visit_comment(comment) }
        else
          visit(new_name)
        end

        align(6) do
          breakable_space
          if old_name.is_a?(SymbolNode)
            text(old_name.value)
          else
            visit(old_name)
          end
        end
      end
    end

    # foo => bar | baz
    #        ^^^^^^^^^
    def visit_alternation_pattern_node(node)
      group do
        visit(node.left)
        text(" ")
        visit_location(node.operator_loc)
        breakable_space
        visit(node.right)
      end
    end

    # a and b
    # ^^^^^^^
    def visit_and_node(node)
      visit_binary(node.left, node.operator_loc, node.right)
    end

    # []
    # ^^
    def visit_array_node(node)
      opening_loc = node.opening_loc
      elements = node.elements

      # If we have no opening location, then this is an implicit array by virtue
      # of an assignment operator. In this case we will print out the elements
      # of the array separated by commas and newlines.
      if opening_loc.nil?
        group { seplist(elements) { |element| visit(element) } }
        return
      end

      # If this is a specially formatted array, we will leave it be and format
      # it according to how the source has it formatted.
      opening = opening_loc.slice
      if opening.start_with?("%")
        group do
          text(opening)
          indent do
            breakable_empty
            seplist(elements, -> { breakable_space }) { |element| visit(element) }
          end
          breakable_empty
          text(node.closing)
        end
        return
      end

      # If this array has no comments on the start of the end location and it
      # has more than 2 elements, we'll check if we can automatically convert it
      # into a %w or %i array.
      closing_loc = node.closing_loc
      if opening_loc.comments.empty? && closing_loc.comments.empty? && elements.length >= 2
        if elements.all? { |element|
             element.is_a?(StringNode) && element.location.comments.empty? &&
               !(content = element.content).empty? &&
               !content.match?(/[\s\[\]\\]/)
           }
          group do
            text("%w[")
            indent do
              breakable_empty
              seplist(elements, -> { breakable_space }) { |element| text(element.content) }
            end
            breakable_empty
            text("]")
          end
          return
        elsif elements.all? { |element|
                element.is_a?(SymbolNode) && element.location.comments.empty?
              }
          group do
            text("%i[")
            indent do
              breakable_empty
              seplist(elements, -> { breakable_space }) { |element| text(element.value) }
            end
            breakable_empty
            text("]")
          end
          return
        end
      end

      # Otherwise we'll format the array normally.
      group do
        visit_location(opening_loc)
        visit_elements(elements, closing_loc.comments)
        breakable_empty
        text("]")
      end
    end

    # foo => [bar]
    #        ^^^^^
    def visit_array_pattern_node(node)
      constant = node.constant
      opening_loc = node.opening_loc

      targets = [*node.requireds, *node.rest, *node.posts]
      implicit_rest = targets.pop if targets.last.is_a?(ImplicitRestNode)

      group do
        visit(constant) unless constant.nil?
        text("[")
        opening_loc.comments.each { |comment| visit_comment(comment) } unless opening_loc.nil?
        visit_elements(targets, node.closing_loc&.comments || [])
        visit(implicit_rest) if implicit_rest
        breakable_empty
        text("]")
      end
    end

    # foo(bar)
    #     ^^^
    def visit_arguments_node(node)
      seplist(node.arguments) { |argument| visit(argument) }
    end

    # { a: 1 }
    #   ^^^^
    def visit_assoc_node(node)
      if node.value.is_a?(HashNode)
        visit_assoc_node_inner(node)
      else
        group { visit_assoc_node_inner(node) }
      end
    end

    # Visit an assoc node and format the key and value.
    private def visit_assoc_node_inner(node)
      operator_loc = node.operator_loc
      value = node.value

      if operator_loc.nil?
        visit(node.key)
        visit_assoc_node_value(value) if !value.nil? && !value.is_a?(ImplicitNode)
      else
        visit(node.key)
        text(" ")
        visit_location(operator_loc)
        visit_assoc_node_value(value)
      end
    end

    # Visit the value of an association node.
    private def visit_assoc_node_value(node)
      if indent_write?(node)
        indent do
          breakable_space
          visit(node)
        end
      else
        text(" ")
        visit(node)
      end
    end

    # Visit an assoc node and format the key as a label.
    private def visit_assoc_node_label(node)
      if node.operator_loc.nil?
        visit(node)
      else
        case (key = node.key).type
        when :interpolated_symbol_node
          opening = key.opening

          if opening.start_with?("%")
            group do
              text(preferred_quote)
              key.parts.each { |part| visit(part) }
              text("#{preferred_quote}:")
            end
          else
            group do
              text(key.opening[1..])
              key.parts.each { |part| visit(part) }
              text(key.closing)
              text(":")
            end
          end
        when :symbol_node
          value = key.value
          if value.match?(/^[_A-Za-z]+$/)
            text(value)
          else
            text("#{preferred_quote}#{value}#{preferred_quote}")
          end

          text(":")
        else
          raise "Unexpected key: #{key.inspect}"
        end

        visit_assoc_node_value(node.value)
      end
    end

    # Visit an assoc node and format the key as a rocket.
    private def visit_assoc_node_rocket(node)
      case (key = node.key).type
      when :interpolated_symbol_node
        opening = key.opening

        if opening.start_with?("%")
          visit(key)
        else
          group do
            text(":")
            text(opening)
            key.parts.each { |part| visit(part) }
            text(key.closing.chomp(":"))
          end
        end
      when :symbol_node
        if key.closing&.end_with?(":")
          text(":")
          text(key.value)
        else
          visit(key)
        end
      else
        visit(key)
      end

      text(" ")
      operator_loc = node.operator_loc
      operator_loc ? visit_location(operator_loc) : text("=>")
      visit_assoc_node_value(node.value)
    end

    # def foo(**); bar(**); end
    #                  ^^
    #
    # { **foo }
    #   ^^^^^
    def visit_assoc_splat_node(node)
      visit_prefix(node.operator_loc, node.value)
    end

    # $+
    # ^^
    def visit_back_reference_read_node(node)
      text(node.slice)
    end

    # begin end
    # ^^^^^^^^^
    def visit_begin_node(node)
      begin_keyword_loc = node.begin_keyword_loc
      statements = node.statements

      rescue_clause = node.rescue_clause
      else_clause = node.else_clause
      ensure_clause = node.ensure_clause

      if begin_keyword_loc.nil?
        group do
          visit(statements) unless statements.nil?

          unless rescue_clause.nil?
            align(-2) do
              breakable_force
              visit(rescue_clause)
            end
          end

          unless else_clause.nil?
            align(-2) do
              breakable_force
              visit(else_clause)
            end
          end

          unless ensure_clause.nil?
            align(-2) do
              breakable_force
              visit(ensure_clause)
            end
          end
        end
      else
        group do
          visit_location(begin_keyword_loc)

          unless statements.nil?
            indent do
              breakable_force
              visit(statements)
            end
          end

          unless rescue_clause.nil?
            breakable_force
            visit(rescue_clause)
          end

          unless else_clause.nil?
            breakable_force
            visit(else_clause)
          end

          unless ensure_clause.nil?
            breakable_force
            visit(ensure_clause)
          end

          breakable_force
          text("end")
        end
      end
    end

    # foo(&bar)
    #     ^^^^
    def visit_block_argument_node(node)
      visit_prefix(node.operator_loc, node.expression)
    end

    # foo { |; bar| }
    #          ^^^
    def visit_block_local_variable_node(node)
      text(node.name.name)
    end

    private def inside_command?(end_index)
      previous = stack[end_index]
      stack[0...end_index].reverse_each.any? do |parent|
        case parent.type
        when :statements_node
          return false
        when :call_node
          if !parent.opening_loc
            return true if parent.arguments
          elsif parent.arguments&.arguments&.include?(previous)
            return false
          end
        end

        previous = parent
        false
      end
    end

    # A block on a keyword or method call.
    def visit_block_node(node)
      parameters = node.parameters
      body = node.body
      opening = node.opening

      # If this is nested anywhere inside of a Command or CommandCall node, then
      # we can't change which operators we're using for the bounds of the block.
      previous = nil
      break_opening, break_closing, flat_opening, flat_closing =
        if inside_command?(-2)
          block_close = opening == "do" ? "end" : "}"
          [opening, block_close, opening, block_close]
        elsif %i[forwarding_super_node super_node].include?(stack[-2].type)
          %w[do end do end]
        elsif stack[0...-1].reverse_each.any? { |parent|
                case parent.type
                when :parentheses_node, :statements_node
                  break false
                when :if_node, :unless_node, :while_node, :until_node
                  break true if parent.predicate == previous
                end

                previous = parent
                false
              }
          %w[{ } { }]
        else
          %w[do end { }]
        end

      parent = stack[-2]

      # If the receiver of this block a call without parentheses, so we need to
      # break the block.
      if parent.is_a?(CallNode) && parent.arguments && parent.opening_loc.nil?
        break_parent
        visit_block_node_break(node, break_opening, break_closing)
      else
        group do
          if_break { visit_block_node_break(node, break_opening, break_closing) }.if_flat do
            text(flat_opening)

            if parameters.is_a?(BlockParametersNode)
              text(" ")
              visit(parameters)
            end

            breakable_space if body || node.closing_loc.comments.any?
            visit_body(body, node.closing_loc.comments, false)
            breakable_space if parameters || body

            text(flat_closing)
          end
        end
      end
    end

    # Visit a block node in the break form.
    private def visit_block_node_break(node, break_opening, break_closing)
      parameters = node.parameters

      text(break_opening)
      node.opening_loc.comments.each { |comment| visit_comment(comment) }

      if parameters.is_a?(BlockParametersNode)
        text(" ")
        visit(parameters)
      end

      visit_body(node.body, node.closing_loc.comments, false)
      breakable_space
      text(break_closing)
    end

    # def foo(&bar); end
    #         ^^^^
    def visit_block_parameter_node(node)
      name = node.name

      group do
        visit_location(node.operator_loc)

        if name
          align(1) do
            breakable_empty
            text(name.name)
          end
        end
      end
    end

    # A block's parameters.
    def visit_block_parameters_node(node)
      parameters = node.parameters
      locals = node.locals
      opening_loc = node.opening_loc

      group do
        if parameters || locals.any?
          if opening_loc
            visit_location(opening_loc)
          else
            text("(")
          end
        end

        remove_breaks(visit(parameters)) if parameters

        if locals.any?
          text("; ")
          seplist(locals) { |local| visit(local) }
        end

        text(node.closing || ")") if parameters || locals.any?
      end
    end

    # break
    # ^^^^^
    #
    # break foo
    # ^^^^^^^^^
    def visit_break_node(node)
      visit_jump("break", node.arguments)
    end

    ATTACH_DIRECTLY = %i[
      array_node
      hash_node
      string_node
      interpolated_string_node
      x_string_node
      interpolated_x_string_node
      if_node
      unless_node
    ].freeze

    # foo
    # ^^^
    #
    # foo.bar
    # ^^^^^^^
    #
    # foo.bar() {}
    # ^^^^^^^^^^^^
    def visit_call_node(node)
      receiver = node.receiver
      message = node.message
      name = node.name

      opening_loc = node.opening_loc
      closing_loc = node.closing_loc

      arguments = [*node.arguments&.arguments]
      block = node.block

      if block.is_a?(BlockArgumentNode)
        arguments << block
        block = nil
      end

      unless node.safe_navigation?
        case name
        when :!
          if message == "not"
            if receiver
              group do
                text("not")

                if opening_loc
                  visit_location(opening_loc)
                else
                  if_break { text("(") }.if_flat { text(" ") }
                end

                indent do
                  breakable_empty
                  visit(receiver)
                end

                if closing_loc
                  breakable_empty
                  visit_location(closing_loc)
                else
                  if_break do
                    breakable_empty
                    text(")")
                  end
                end
              end
            else
              text("not()")
            end

            return
          end

          if arguments.empty? && block.nil?
            visit_prefix(node.message_loc, receiver)
            return
          end
        when :+@, :-@, :~
          if arguments.empty? && block.nil?
            visit_prefix(node.message_loc, receiver)
            return
          end
        when :+, :-, :*, :/, :%, :==, :===, :!=, :!~, :=~, :>, :<, :>=, :<=, :<=>, :<<, :>>, :&, :|,
             :^
          if arguments.length == 1 && block.nil?
            visit_binary(receiver, node.message_loc, arguments.first)
            return
          end
        when :**
          if arguments.length == 1 && block.nil?
            group do
              visit(receiver)
              text("**")
              indent do
                breakable_empty
                seplist(arguments) { |argument| visit(argument) }
              end
            end

            return
          end
        when :[]
          group do
            visit(receiver)
            text("[")

            if arguments.any?
              indent do
                breakable_empty
                seplist(arguments) { |argument| visit(argument) }
              end

              breakable_empty
            end

            text("]")

            if block
              text(" ")
              visit(block)
            end
          end

          return
        when :[]=
          if arguments.any?
            group do
              *before, after = arguments

              group do
                visit(receiver)
                text("[")

                if before.any?
                  indent do
                    breakable_empty
                    seplist(before) { |argument| visit(argument) }
                  end
                  breakable_empty
                end

                text("]")
              end

              text(" ")
              group do
                text("=")
                indent do
                  breakable_space
                  visit(after)
                end
              end

              if block
                text(" ")
                visit(block)
              end
            end
          else
            group do
              visit(receiver)
              text("[]")

              if block
                text(" ")
                visit(block)
              end
            end
          end

          return
        when :to, :to_not, :not_to
          # Very special handling here for RSpec. Methods on expectation objects
          # are almost always used without parentheses. This can result in
          # pretty ugly formatting, because the DSL gets super confusing.
          if opening_loc.nil?
            group do
              visit(receiver) if receiver
              visit_call_node_call_operator(node.call_operator_loc) if node.call_operator_loc
              visit_location(node.message_loc) if node.message_loc
              visit_call_node_rhs(node, 0)
            end

            return
          end
        end
      end

      # Now that we've passed through all of the special handling for specific
      # method names, we can handle the general case of a method call. In this
      # case we'll first build up a call chain for all of the calls in a row.
      # This could potentially be just a single method call.
      chain = [node]
      current = node

      while (receiver = current.receiver).is_a?(CallNode)
        chain.unshift(receiver)
        current = receiver
      end

      chain.unshift(receiver) if receiver

      if chain.length > 1
        if !ATTACH_DIRECTLY.include?(receiver&.type) &&
             chain[0...-1].all? { |node|
               !node.is_a?(CallNode) ||
                 (
                   ((node.opening_loc.nil? && !node.arguments) || node.name == :[]) &&
                     !node.block &&
                     node.location.comments.none? &&
                     !node.call_operator_loc&.comments&.any? &&
                     !node.message_loc&.comments&.any?
                 )
             } &&
             !chain[-1].call_operator_loc&.comments&.any? &&
             !chain[-1].message_loc&.comments&.any?
          # Special handling here for the case that we have a call chain that is
          # just method names and operators, ending with a call that has
          # anything else. In this case we'll put everything on the same line
          # and break the chain at the end. This can look like:
          #
          #     foo.bar.baz { |qux| qux }
          #
          # In this case if it gets broken, we don't want multiple lines of
          # method calls, instead we want to only break the block at the end,
          # like:
          #
          #     foo.bar.baz do |qux|
          #       qux
          #     end
          #
          group do
            *rest, last = chain
            doc =
              align(0) do
                visit(rest.shift) unless rest.first.is_a?(CallNode)

                rest.each do |node|
                  visit_call_node_call_operator(node.call_operator_loc)

                  if node.name == :[]
                    visit_call_node_rhs(node, 0)
                  else
                    visit_location(node.message_loc)
                  end
                end

                visit_call_node_call_operator(last.call_operator_loc)
              end

            group do
              visit_location(last.message_loc) if last.message_loc && last.name != :[]
              visit_call_node_rhs(last, last_position(doc) + (last.message&.length || 0) + 1)
            end
          end
        else
          # Otherwise we'll break the chain at each node, indenting all of the
          # calls beyond the first one by one level of indentation.
          group do
            first, *rest = chain

            # If a call operator has a trailing comment on it, then we need to
            # put it on the previous line. In this case we need to communicate
            # to the next iteration in the loop that we have already printed the
            # call operator.
            call_operator_printed = false

            case first.type
            when :call_node
              # If the first node in the chain is a call node, we only need to
              # print the message because we will not have a receiver and we
              # will handle the arguments and block in the loop below.
              visit_location(first.message_loc)
              visit_call_node_rhs(first, first.message.length + 1)

              # If the first call in the chain has a trailing comment on its
              # call operator, then we need to print it within this group.
              if (subseq = rest.first) &&
                   (
                     (call_operator_loc = subseq.call_operator_loc)&.trailing_comments&.any? ||
                       subseq.message_loc&.leading_comments&.any?
                   )
                call_operator_printed = true
                visit_call_node_call_operator(call_operator_loc)
              end

              if first.block.is_a?(BlockNode)
                node = rest.shift

                group do
                  if rest.any?
                    node.location.leading_comments.each { |comment| visit_comment(comment) }
                  end

                  visit_call_node_call_operator(node.call_operator_loc) unless call_operator_printed
                  visit_location(node.message_loc) if node.message_loc && node.name != :[]
                  visit_call_node_rhs(node, (message&.length || 0) + 2)

                  if rest.any?
                    node.location.trailing_comments.each { |comment| visit_comment(comment) }

                    # If the first call in the chain has a trailing comment on its
                    # call operator, then we need to print it within this group.
                    if (subseq = rest.first) &&
                         (
                           (
                             call_operator_loc = subseq.call_operator_loc
                           )&.trailing_comments&.any? ||
                             subseq.message_loc&.leading_comments&.any?
                         )
                      call_operator_printed = true
                      visit_call_node_call_operator(call_operator_loc)
                    else
                      call_operator_printed = false
                    end
                  end
                end
              end
            when *ATTACH_DIRECTLY
              # Certain nodes we want to attach our message directly to them,
              # because it looks strange to have a message on a separate line.
              group do
                visit(first)
                node = rest.shift

                group do
                  if rest.any?
                    node.location.leading_comments.each { |comment| visit_comment(comment) }
                  end

                  visit_call_node_call_operator(node.call_operator_loc)
                  visit_location(node.message_loc) if node.message_loc && node.name != :[]
                  visit_call_node_rhs(node, (message&.length || 0) + 2)

                  if rest.any?
                    node.location.trailing_comments.each { |comment| visit_comment(comment) }

                    # If the first call in the chain has a trailing comment on its
                    # call operator, then we need to print it within this group.
                    if (subseq = rest.first) &&
                         (
                           (
                             call_operator_loc = subseq.call_operator_loc
                           )&.trailing_comments&.any? ||
                             subseq.message_loc&.leading_comments&.any?
                         )
                      call_operator_printed = true
                      visit_call_node_call_operator(call_operator_loc)
                    end
                  end
                end
              end
            else
              # Otherwise, we'll format the receiver of the first member of the
              # call chain and then indent all of the calls by one level.
              visit(first)

              # If the first call in the chain has a trailing comment on its
              # call operator, then we need to print it within this group.
              if (subseq = rest.first) &&
                   (
                     (call_operator_loc = subseq.call_operator_loc)&.trailing_comments&.any? ||
                       subseq.message_loc&.leading_comments&.any?
                   )
                call_operator_printed = true
                visit_call_node_call_operator(call_operator_loc)
              end
            end

            inside_command = inside_command?(-1)
            indent do
              rest.each_with_index do |node, index|
                stack << node

                if inside_command && !call_operator_printed
                # Do not break the chain if we're inside a command, because
                # that would lead to this method call being placed on the
                # command as opposed to this chain.
                elsif node.name == :[]
                # If this is a call to `[]`, then we don't want to break the
                # chain here, because we want to effectively treat it as a
                # postfix operator.
                elsif node.name == :not && (receiver = node.receiver).is_a?(CallNode) &&
                        receiver.name == :where &&
                        !receiver.arguments &&
                        !receiver.block
                # Generally we will always break the chain at each node.
                # However, there is some nice behavior here if we have a call
                # chain with `where.not` in it (common in Rails). In that case
                # it's nice to keep the `not` on the same line as the `where`.
                elsif call_operator_printed &&
                        node.message_loc&.leading_comments&.any? { |comment|
                          comment.is_a?(EmbDocComment)
                        }
                # If we have already printed the call operator and the message
                # location has a leading embdoc comment, then we already have
                # a newline printed in this chain.
                else
                  breakable_empty
                end

                group do
                  if index != rest.length - 1
                    node.location.leading_comments.each { |comment| visit_comment(comment) }
                  end

                  visit_call_node_call_operator(node.call_operator_loc) unless call_operator_printed
                  visit_location(node.message_loc) if node.message_loc && node.name != :[]
                  visit_call_node_rhs(node, (node.message&.length || 0) + 2)

                  if index != rest.length - 1
                    node.location.trailing_comments.each { |comment| visit_comment(comment) }

                    # If the call operator has a trailing comment, then we need
                    # to print it within this group.
                    if (subseq = rest[index + 1]) &&
                         (
                           (
                             call_operator_loc = subseq.call_operator_loc
                           )&.trailing_comments&.any? ||
                             subseq.message_loc&.leading_comments&.any?
                         )
                      call_operator_printed = true
                      visit_call_node_call_operator(call_operator_loc)
                    else
                      call_operator_printed = false
                    end
                  end
                end

                stack.pop
              end
            end
          end
        end
      else
        # If there is no call chain, then it's not possible that there's a
        # receiver. In this case we'll visit the message and then the arguments
        # and block.
        group do
          visit_location(node.message_loc)
          visit_call_node_rhs(node, node.message.length + 1)
        end
      end
    end

    private def visit_call_node_call_operator(location)
      visit_location(location, location.slice == "&." ? "&." : ".") if location
    end

    private def visit_call_node_rhs(node, position)
      arguments = [*node.arguments&.arguments]
      block = node.block

      if block.is_a?(BlockArgumentNode)
        arguments << block
        block = nil
      end

      if arguments.length == 1 && node.name.end_with?("=") &&
           !%i[== === != >= <=].include?(node.name) &&
           block.nil?
        argument = arguments.first
        text(" =")

        if indent_write?(argument)
          indent do
            breakable_space
            visit(argument)
          end
        else
          text(" ")
          visit(argument)
        end
      elsif !node.opening_loc.nil? && arguments.any? && !node.closing_loc.nil?
        group do
          visit_location(node.message_loc) if node.name == :[] && node.call_operator_loc
          visit_location(node.opening_loc)
          indent do
            breakable_empty
            seplist(arguments) { |argument| visit(argument) }

            if trailing_comma && !arguments.last.is_a?(BlockArgumentNode) &&
                 !(
                    arguments.length == 1 && (argument = arguments.first).is_a?(CallNode) &&
                      argument.arguments &&
                      argument.opening_loc.nil?
                  )
              if_break { text(",") }
            end
          end
          breakable_empty
          visit_location(node.closing_loc)
        end
      elsif arguments.any?
        text(" ")
        group { visit_call_node_command_arguments(node, arguments, position) }
      elsif node.opening_loc && node.closing_loc
        visit_location(node.opening_loc)
        visit_location(node.closing_loc)
      end

      if block
        text(" ")
        visit(block)
      end
    end

    # Align the contents of the given node with the last position. This is used
    # to align method calls without parentheses.
    private def visit_call_node_command_arguments(node, arguments, position)
      if node.arguments && node.arguments.arguments.length == 1
        argument = node.arguments.arguments.first

        case argument.type
        when :def_node
          seplist(arguments) { |argument| visit(argument) }
          return
        when :call_node
          if argument.opening_loc.nil?
            visit_call_node_command_arguments(argument, arguments, position)
            return
          elsif argument.block.is_a?(BlockNode)
            seplist(arguments) { |argument| visit(argument) }
            return
          end
        end
      end

      align(position > (print_width / 2) ? 0 : position) do
        seplist(arguments) { |argument| visit(argument) }
      end
    end

    # foo.bar += baz
    # ^^^^^^^^^^^^^^^
    def visit_call_operator_write_node(node)
      receiver = node.receiver
      call_operator_loc = node.call_operator_loc

      visit_write(node.binary_operator_loc, node.value) do
        group do
          if receiver
            visit(receiver)
            visit_call_node_call_operator(call_operator_loc)
          end

          text(node.message)
        end
      end
    end

    # foo.bar &&= baz
    # ^^^^^^^^^^^^^^^
    def visit_call_and_write_node(node)
      receiver = node.receiver
      call_operator_loc = node.call_operator_loc

      visit_write(node.operator_loc, node.value) do
        group do
          if receiver
            visit(receiver)
            visit_call_node_call_operator(call_operator_loc)
          end

          text(node.message)
        end
      end
    end

    # foo.bar ||= baz
    # ^^^^^^^^^^^^^^^
    def visit_call_or_write_node(node)
      receiver = node.receiver
      call_operator_loc = node.call_operator_loc

      visit_write(node.operator_loc, node.value) do
        group do
          if receiver
            visit(receiver)
            visit_call_node_call_operator(call_operator_loc)
          end

          text(node.message)
        end
      end
    end

    # foo.bar, = 1
    # ^^^^^^^
    def visit_call_target_node(node)
      group do
        visit(node.receiver)
        visit_location(node.call_operator_loc)
        text(node.message)
      end
    end

    # foo => bar => baz
    #        ^^^^^^^^^^
    def visit_capture_pattern_node(node)
      visit_binary(node.value, node.operator_loc, node.target)
    end

    # case foo; when bar; end
    # ^^^^^^^^^^^^^^^^^^^^^^^
    def visit_case_node(node)
      visit_case(
        node.case_keyword_loc,
        node.predicate,
        node.conditions,
        node.else_clause,
        node.end_keyword_loc
      )
    end

    # case foo; in bar; end
    # ^^^^^^^^^^^^^^^^^^^^^
    def visit_case_match_node(node)
      visit_case(
        node.case_keyword_loc,
        node.predicate,
        node.conditions,
        node.else_clause,
        node.end_keyword_loc
      )
    end

    private def visit_case(case_keyword_loc, predicate, conditions, else_clause, end_keyword_loc)
      group do
        group do
          visit_location(case_keyword_loc)

          if predicate
            text(" ")
            align(5) { visit(predicate) }
          end
        end

        breakable_force
        seplist(conditions, -> { breakable_force }) { |condition| visit(condition) }

        if else_clause
          breakable_force
          visit(else_clause)
        end

        indent do
          end_keyword_loc.comments.each do |comment|
            breakable_force
            text(comment.location.slice)
          end
        end

        breakable_force
        text("end")
      end
    end

    # class Foo; end
    # ^^^^^^^^^^^^^^
    def visit_class_node(node)
      class_keyword_loc = node.class_keyword_loc
      inheritance_operator_loc = node.inheritance_operator_loc
      superclass = node.superclass

      group do
        group do
          visit_location(class_keyword_loc)

          if class_keyword_loc.comments.any?
            indent do
              breakable_space
              visit(node.constant_path)
            end
          else
            text(" ")
            visit(node.constant_path)
          end

          if superclass
            text(" ")
            visit_location(inheritance_operator_loc)

            if inheritance_operator_loc.comments.any?
              indent do
                breakable_space
                visit(superclass)
              end
            else
              text(" ")
              visit(superclass)
            end
          end
        end

        visit_body(node.body, node.end_keyword_loc.comments)
        breakable_force
        text("end")
      end
    end

    # @@foo
    # ^^^^^
    def visit_class_variable_read_node(node)
      text(node.name.name)
    end

    # @@foo = 1
    # ^^^^^^^^^
    #
    # @@foo, @@bar = 1
    # ^^^^^  ^^^^^
    def visit_class_variable_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @@foo += bar
    # ^^^^^^^^^^^^
    def visit_class_variable_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { text(node.name.name) }
    end

    # @@foo &&= bar
    # ^^^^^^^^^^^^^
    def visit_class_variable_and_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @@foo ||= bar
    # ^^^^^^^^^^^^^
    def visit_class_variable_or_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @@foo, = bar
    # ^^^^^
    def visit_class_variable_target_node(node)
      text(node.name.name)
    end

    # Foo
    # ^^^
    def visit_constant_read_node(node)
      text(node.name.name)
    end

    # Foo = 1
    # ^^^^^^^
    #
    # Foo, Bar = 1
    # ^^^  ^^^
    def visit_constant_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # Foo += bar
    # ^^^^^^^^^^^
    def visit_constant_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { text(node.name.name) }
    end

    # Foo &&= bar
    # ^^^^^^^^^^^^
    def visit_constant_and_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # Foo ||= bar
    # ^^^^^^^^^^^^
    def visit_constant_or_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # Foo, = bar
    # ^^^
    def visit_constant_target_node(node)
      text(node.name.name)
    end

    # Foo::Bar
    # ^^^^^^^^
    def visit_constant_path_node(node)
      parent = node.parent

      group do
        visit(parent) if parent
        visit_location(node.delimiter_loc)
        indent do
          breakable_empty
          visit_location(node.name_loc)
        end
      end
    end

    # Foo::Bar = 1
    # ^^^^^^^^^^^^
    #
    # Foo::Foo, Bar::Bar = 1
    # ^^^^^^^^  ^^^^^^^^
    def visit_constant_path_write_node(node)
      visit_write(node.operator_loc, node.value) { visit(node.target) }
    end

    # Foo::Bar += baz
    # ^^^^^^^^^^^^^^^
    def visit_constant_path_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { visit(node.target) }
    end

    # Foo::Bar &&= baz
    # ^^^^^^^^^^^^^^^^
    def visit_constant_path_and_write_node(node)
      visit_write(node.operator_loc, node.value) { visit(node.target) }
    end

    # Foo::Bar ||= baz
    # ^^^^^^^^^^^^^^^^
    def visit_constant_path_or_write_node(node)
      visit_write(node.operator_loc, node.value) { visit(node.target) }
    end

    # Foo::Bar, = baz
    # ^^^^^^^^
    def visit_constant_path_target_node(node)
      parent = node.parent

      group do
        visit(parent) if parent
        visit_location(node.delimiter_loc)
        indent do
          breakable_empty
          visit_location(node.name_loc)
        end
      end
    end

    # def foo; end
    # ^^^^^^^^^^^^
    #
    # def self.foo; end
    # ^^^^^^^^^^^^^^^^^
    def visit_def_node(node)
      receiver = node.receiver
      name_loc = node.name_loc
      parameters = node.parameters
      lparen_loc = node.lparen_loc
      rparen_loc = node.rparen_loc

      group do
        group do
          group do
            text("def")
            text(" ") if !receiver.nil? || name_loc.leading_comments.none?

            group do
              if receiver
                visit(receiver)
                text(".")
              end

              visit_location(name_loc)
            end
          end

          if parameters
            lparen_loc ? visit_location(lparen_loc) : text("(")

            if parameters
              indent do
                breakable_empty
                visit(parameters)
              end
            end

            breakable_empty
            text(")")

            # Very specialized behavior here where inline comments do not force
            # a break parent. This should probably be an option on
            # visit_location.
            rparen_loc&.comments&.each do |comment|
              if comment.is_a?(InlineComment)
                line_suffix(COMMENT_PRIORITY) do
                  comment.trailing? ? text(" ") : breakable
                  text(comment.location.slice)
                end
              else
                breakable_force
                trim
                text(comment.location.slice.rstrip)
              end
            end
          else
            visit_location(lparen_loc) if lparen_loc
            breakable_empty if lparen_loc&.comments&.any?
            visit_location(rparen_loc) if rparen_loc
          end
        end

        if node.equal_loc
          text(" ")
          visit_location(node.equal_loc)
          text(" ")
          visit(node.body)
        else
          visit_body(node.body, node.end_keyword_loc.comments)
          breakable_force
          text("end")
        end
      end
    end

    # defined? a
    # ^^^^^^^^^^
    #
    # defined?(a)
    # ^^^^^^^^^^^
    def visit_defined_node(node)
      group do
        visit_location(node.keyword_loc)
        if (lparen_loc = node.lparen_loc)
          visit_location(lparen_loc)
        else
          text("(")
        end

        visit_body(node.value, node.rparen_loc&.comments || [], false)
        breakable_empty
        text(")")
      end
    end

    # if foo then bar else baz end
    #                 ^^^^^^^^^^^^
    def visit_else_node(node)
      group do
        visit_location(node.else_keyword_loc)
        visit_body(node.statements, node.end_keyword_loc.comments)
      end
    end

    # "foo #{bar}"
    #      ^^^^^^
    def visit_embedded_statements_node(node)
      group do
        visit_location(node.opening_loc)

        if (statements = node.statements)
          indent do
            breakable_empty
            visit(statements)
          end
          breakable_empty
        end

        text("}")
      end
    end

    # "foo #@bar"
    #      ^^^^^
    def visit_embedded_variable_node(node)
      group do
        text("\#{")
        indent do
          breakable_empty
          visit(node.variable)
        end
        breakable_empty
        text("}")
      end
    end

    # begin; foo; ensure; bar; end
    #             ^^^^^^^^^^^^
    def visit_ensure_node(node)
      group do
        visit_location(node.ensure_keyword_loc)
        visit_body(node.statements, node.end_keyword_loc.comments)
      end
    end

    # false
    # ^^^^^
    def visit_false_node(_node)
      text("false")
    end

    # foo => [*, bar, *]
    #        ^^^^^^^^^^^
    def visit_find_pattern_node(node)
      constant = node.constant

      group do
        visit(constant) if constant
        text("[")

        indent do
          breakable_empty
          seplist([node.left, *node.requireds, node.right]) { |element| visit(element) }
        end

        breakable_empty
        text("]")
      end
    end

    # if foo .. bar; end
    #    ^^^^^^^^^^
    def visit_flip_flop_node(node)
      left = node.left
      right = node.right

      group do
        visit(left) if left
        text(" ")
        visit_location(node.operator_loc)

        if right
          indent do
            breakable_space
            visit(right)
          end
        end
      end
    end

    # 1.0
    # ^^^
    def visit_float_node(node)
      text(node.slice)
    end

    # for foo in bar do end
    # ^^^^^^^^^^^^^^^^^^^^^
    def visit_for_node(node)
      group do
        text("for ")
        group { visit(node.index) }
        text(" in ")
        group { visit(node.collection) }
        visit_body(node.statements, node.end_keyword_loc.comments)
        breakable_force
        text("end")
      end
    end

    # def foo(...); bar(...); end
    #                   ^^^
    def visit_forwarding_arguments_node(_node)
      text("...")
    end

    # def foo(...); end
    #         ^^^
    def visit_forwarding_parameter_node(_node)
      text("...")
    end

    # super
    # ^^^^^
    #
    # super {}
    # ^^^^^^^^
    def visit_forwarding_super_node(node)
      block = node.block

      if block
        group do
          text("super ")
          visit(block)
        end
      else
        text("super")
      end
    end

    # $foo
    # ^^^^
    def visit_global_variable_read_node(node)
      text(node.name.name)
    end

    # $foo = 1
    # ^^^^^^^^
    #
    # $foo, $bar = 1
    # ^^^^  ^^^^
    def visit_global_variable_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # $foo += bar
    # ^^^^^^^^^^^
    def visit_global_variable_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { text(node.name.name) }
    end

    # $foo &&= bar
    # ^^^^^^^^^^^^
    def visit_global_variable_and_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # $foo ||= bar
    # ^^^^^^^^^^^^
    def visit_global_variable_or_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # $foo, = bar
    # ^^^^
    def visit_global_variable_target_node(node)
      text(node.name.name)
    end

    # {}
    # ^^
    def visit_hash_node(node)
      elements = node.elements

      group_if(!stack[-2].is_a?(AssocNode)) do
        if elements.any? { |element| element.value.is_a?(ImplicitNode) }
          visit_hash_node_layout(node) { |element| visit(element) }
        elsif elements.all? { |element|
                !element.is_a?(AssocNode) || element.operator_loc.nil? ||
                  element.key.is_a?(InterpolatedSymbolNode) ||
                  (
                    element.key.is_a?(SymbolNode) && (value = element.key.value) &&
                      value.match?(/^[_A-Za-z]/) &&
                      !value.end_with?("=")
                  )
              }
          visit_hash_node_layout(node) { |element| visit_assoc_node_label(element) }
        else
          visit_hash_node_layout(node) { |element| visit_assoc_node_rocket(element) }
        end
      end
    end

    # Visit a hash node and yield out each plain association element for
    # formatting by the caller.
    private def visit_hash_node_layout(node)
      elements = node.elements

      group do
        visit_location(node.opening_loc)
        indent do
          if elements.any?
            breakable_space
            seplist(elements) do |element|
              if element.is_a?(AssocNode)
                if element.value.is_a?(HashNode)
                  yield element
                else
                  group { yield element }
                end
              else
                visit(element)
              end
            end
            if_break { text(",") } if trailing_comma
          end

          node.closing_loc.comments.each do |comment|
            breakable_force
            text(comment.location.slice)
          end
        end

        elements.any? ? breakable_space : breakable_empty
        text("}")
      end
    end

    # foo => {}
    #        ^^
    def visit_hash_pattern_node(node)
      constant = node.constant
      opening_loc = node.opening_loc
      closing_loc = node.closing_loc

      elements = [*node.elements, *node.rest]

      if constant
        group do
          visit(constant)
          text("[")
          opening_loc.comments.each { |comment| visit_comment(comment) } if opening_loc
          visit_elements(elements, closing_loc&.comments || [])
          breakable_empty
          text("]")
        end
      else
        group do
          text("{")
          opening_loc.comments.each { |comment| visit_comment(comment) } if opening_loc
          visit_elements_spaced(elements, closing_loc&.comments || [])
          elements.any? ? breakable_space : breakable_empty
          text("}")
        end
      end
    end

    # if foo then bar end
    # ^^^^^^^^^^^^^^^^^^^
    #
    # bar if foo
    # ^^^^^^^^^^
    #
    # foo ? bar : baz
    # ^^^^^^^^^^^^^^^
    def visit_if_node(node)
      if_keyword_loc = node.if_keyword_loc
      if_keyword = node.if_keyword

      statements = node.statements
      subsequent = node.subsequent

      if if_keyword == "elsif"
        # If we get here, then this is an if node that was expressed as an elsif
        # clause in a larger chain. In this case we can simplify formatting
        # because there are many things we don't need to check.
        group do
          visit_location(if_keyword_loc)
          text(" ")
          align(6) { visit(node.predicate) }

          if subsequent
            visit_body(statements, [], true)
            breakable_force
            visit(subsequent)
          else
            visit_body(statements, node.end_keyword_loc.comments, true)
          end
        end
      elsif !if_keyword_loc
        # If there is no keyword location, then this if node was expressed as a
        # ternary. In this case we know quite a bit about the structure of the
        # node and will format it quite differently.
        truthy = statements.body.first
        falsy = subsequent.statements.body.first

        if stack[-2].is_a?(ParenthesesNode) || forced_ternary?(truthy) || forced_ternary?(falsy)
          group { visit_ternary_node_flat(node, truthy, falsy) }
        else
          group do
            if_break { visit_ternary_node_break(node, truthy, falsy) }.if_flat do
              visit_ternary_node_flat(node, truthy, falsy)
            end
          end
        end
      elsif !statements || subsequent || contains_conditional?(statements.body.first)
        # If there are no statements, no subsequent clause, or the body of the
        # node has a conditional, then we will format the node in a break form,
        # which is to say the keyword first.
        group do
          visit_if_node_break(node)
          break_parent
        end
      elsif contains_write?(node.predicate) || contains_write?(statements)
        # If the predicate or the body of the node contains a write, then
        # changing the form of the conditional could impact the meaning of the
        # expression. In this case we will respect the form of the source.
        if node.end_keyword_loc.nil?
          group { visit_if_node_flat(node) }
        else
          group do
            visit_if_node_break(node)
            break_parent
          end
        end
      else
        # Otherwise, we will attempt to format the node in the flat form if it
        # fits, and otherwise we will break it into multiple lines.
        group do
          if_break { visit_if_node_break(node) }.if_flat do
            ensure_parentheses { visit_if_node_flat(node) }
          end
        end
      end
    end

    private def forced_ternary?(node)
      case node.type
      when :alias_node, :alias_global_variable_node, :break_node, :if_node, :unless_node,
           :lambda_node, :multi_write_node, :next_node, :rescue_modifier_node, :super_node,
           :forwarding_super_node, :undef_node, :yield_node, :return_node, :call_and_write_node,
           :call_or_write_node, :call_operator_write_node, :class_variable_write_node,
           :class_variable_and_write_node, :class_variable_or_write_node,
           :class_variable_operator_write_node, :constant_write_node, :constant_and_write_node,
           :constant_or_write_node, :constant_operator_write_node, :constant_path_write_node,
           :constant_path_and_write_node, :constant_path_or_write_node,
           :constant_path_operator_write_node, :global_variable_write_node,
           :global_variable_and_write_node, :global_variable_or_write_node,
           :global_variable_operator_write_node, :instance_variable_write_node,
           :instance_variable_and_write_node, :instance_variable_or_write_node,
           :instance_variable_operator_write_node, :local_variable_write_node,
           :local_variable_and_write_node, :local_variable_or_write_node,
           :local_variable_operator_write_node
        true
      when :call_node
        node.receiver && node.opening_loc.nil?
      when :string_node, :interpolated_string_node, :x_string_node, :interpolated_x_string_node
        node.heredoc?
      else
        false
      end
    end

    private def visit_ternary_node_flat(node, truthy, falsy)
      visit(node.predicate)
      text(" ?")
      indent do
        breakable_space
        visit(truthy)
        text(" :")
        breakable_space
        visit(falsy)
      end
    end

    private def visit_ternary_node_break(node, truthy, falsy)
      group do
        text("if ")
        align(3) { visit(node.predicate) }
      end

      indent do
        breakable_space
        visit(truthy)
      end

      breakable_space
      text("else")

      indent do
        breakable_space
        visit(falsy)
      end

      breakable_space
      text("end")
    end

    # Visit an if node in the break form.
    private def visit_if_node_break(node)
      statements = node.statements
      subsequent = node.subsequent

      group do
        visit_location(node.if_keyword_loc)
        text(" ")
        align(3) { visit(node.predicate) }
      end

      if subsequent
        visit_body(statements, [], false)
        breakable_space
        visit(subsequent)
      else
        visit_body(statements, node.end_keyword_loc&.comments || [], false)
      end

      breakable_space
      text("end")
    end

    # Visit an if node in the flat form.
    private def visit_if_node_flat(node)
      visit(node.statements)
      text(" if ")
      visit(node.predicate)
    end

    # 1i
    def visit_imaginary_node(node)
      text(node.slice)
    end

    # { foo: }
    #   ^^^^
    def visit_implicit_node(node)
      # Nothing, because it represents implicit syntax.
    end

    # foo { |bar,| }
    #           ^
    def visit_implicit_rest_node(_node)
      text(",")
    end

    # case foo; in bar; end
    # ^^^^^^^^^^^^^^^^^^^^^
    def visit_in_node(node)
      statements = node.statements

      group do
        text("in ")
        align(3) { visit(node.pattern) }

        if statements
          indent do
            breakable_force
            visit(statements)
          end
        end
      end
    end

    # foo[bar] += baz
    # ^^^^^^^^^^^^^^^
    def visit_index_operator_write_node(node)
      arguments = [*node.arguments, *node.block]

      visit_write(node.binary_operator_loc, node.value) do
        group do
          visit(node.receiver)
          visit_location(node.opening_loc)

          if arguments.any?
            indent do
              breakable_empty
              seplist(arguments) { |argument| visit(argument) }
            end
          end

          breakable_empty
          text("]")
        end
      end
    end

    # foo[bar] &&= baz
    # ^^^^^^^^^^^^^^^^
    def visit_index_and_write_node(node)
      arguments = [*node.arguments, *node.block]

      visit_write(node.operator_loc, node.value) do
        group do
          visit(node.receiver)
          visit_location(node.opening_loc)

          if arguments.any?
            indent do
              breakable_empty
              seplist(arguments) { |argument| visit(argument) }
            end
          end

          breakable_empty
          text("]")
        end
      end
    end

    # foo[bar] ||= baz
    # ^^^^^^^^^^^^^^^^
    def visit_index_or_write_node(node)
      arguments = [*node.arguments, *node.block]

      visit_write(node.operator_loc, node.value) do
        group do
          visit(node.receiver)
          visit_location(node.opening_loc)

          if arguments.any?
            indent do
              breakable_empty
              seplist(arguments) { |argument| visit(argument) }
            end
          end

          breakable_empty
          text("]")
        end
      end
    end

    # foo[bar], = 1
    # ^^^^^^^^
    def visit_index_target_node(node)
      group do
        visit(node.receiver)
        visit_location(node.opening_loc)

        if (arguments = (node.arguments&.arguments || [])).any?
          indent do
            breakable_empty
            seplist(arguments) { |argument| visit(argument) }
          end
        end

        breakable_empty
        text("]")
      end
    end

    # @foo
    # ^^^^
    def visit_instance_variable_read_node(node)
      text(node.name.name)
    end

    # @foo = 1
    # ^^^^^^^^
    #
    # @foo, @bar = 1
    # ^^^^  ^^^^
    def visit_instance_variable_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @foo += bar
    # ^^^^^^^^^^^
    def visit_instance_variable_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { text(node.name.name) }
    end

    # @foo &&= bar
    # ^^^^^^^^^^^^
    def visit_instance_variable_and_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @foo ||= bar
    # ^^^^^^^^^^^^
    def visit_instance_variable_or_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # @foo, = bar
    # ^^^^
    def visit_instance_variable_target_node(node)
      text(node.name.name)
    end

    # 1
    # ^
    def visit_integer_node(node)
      slice = node.slice

      if slice.match?(/^[1-9]\d{4,}$/)
        # If it's a plain integer and it doesn't have any underscores separating
        # the values, then we're going to insert them every 3 characters
        # starting from the right.
        index = (slice.length + 2) % 3
        text("  #{slice}"[index..].scan(/.../).join("_").strip)
      else
        text(slice)
      end
    end

    # if /foo #{bar}/ then end
    #    ^^^^^^^^^^^^
    def visit_interpolated_match_last_line_node(node)
      visit_regular_expression_node_parts(node, node.parts)
    end

    # /foo #{bar}/
    # ^^^^^^^^^^^^
    def visit_interpolated_regular_expression_node(node)
      visit_regular_expression_node_parts(node, node.parts)
    end

    # "foo #{bar}"
    # ^^^^^^^^^^^^
    def visit_interpolated_string_node(node)
      parts = node.parts

      if node.heredoc?
        # First, if this interpolated string was expressed as a heredoc, then
        # we'll maintain that formatting and print it out again as a heredoc.
        visit_heredoc(node, parts)
      elsif parts.length > 1 && independent_string?(parts[0]) && independent_string?(parts[1])
        # Next, we'll check if this string is composed of multiple parts that
        # have their own opening. If it is, then this actually represents string
        # concatenation and not a single string literal. In this case we'll
        # format each on their own with appropriate spacing.
        group do
          visit(parts[0])
          if_break { text(" \\") }
          indent do
            breakable_space
            seplist(
              parts[1..],
              -> do
                if_break { text(" \\") }
                breakable_space
              end
            ) { |part| visit(part) }
          end
        end
      else
        # Finally, if it's a regular interpolated string, we'll forward this on
        # to our generic string node formatter.
        visit_string_node_parts(node, node.parts)
      end
    end

    private def independent_string?(node)
      case node.type
      when :string_node
        !node.opening_loc.nil?
      when :interpolated_string_node
        !node.opening_loc.nil?
      else
        false
      end
    end

    # :"foo #{bar}"
    # ^^^^^^^^^^^^^
    def visit_interpolated_symbol_node(node)
      opening = node.opening
      parts = node.parts

      # First, we'll check if we don't have an opening. If we don't, then this
      # is inside of a %I literal and we should just print the parts as-is.
      return group { parts.each { |part| visit(part) } } if opening.nil?

      # If we're inside of an assoc node as the key, then it will handle
      # printing the : on its own since it could change sides.
      parent = stack[-2]
      hash_key = parent.is_a?(AssocNode) && parent.key == node

      # Here we determine the quotes to use for an interpolated symbol. It's
      # bound by a lot of rules because it could be in many different contexts
      # with many different kinds of escaping.
      opening_quote, closing_quote =
        if opening.start_with?("%s")
          # Here we're going to check if there is a closing character, a new
          # line, or a quote in the content of the dyna symbol. If there is,
          # then quoting could get weird, so just bail out and stick to the
          # original quotes in the source.
          matching = quotes_matching(opening[2])
          pattern = /[\n#{Regexp.escape(matching)}'"]/

          # This check is to ensure we don't find a matching quote inside of the
          # symbol that would be confusing.
          matched = parts.any? { |part| part.is_a?(StringNode) && part.content.match?(pattern) }

          if matched
            [opening, matching]
          elsif quotes_locked?(parts)
            ["#{":" unless hash_key}'", "'"]
          else
            ["#{":" unless hash_key}#{preferred_quote}", preferred_quote]
          end
        elsif quotes_locked?(parts)
          if hash_key
            if opening.start_with?(":")
              [opening[1..], "#{opening[1..]}:"]
            else
              [opening, node.closing]
            end
          else
            [opening, node.closing]
          end
        else
          [hash_key ? preferred_quote : ":#{preferred_quote}", preferred_quote]
        end

      group do
        text(opening_quote)
        parts.each do |part|
          if part.is_a?(StringNode)
            value = quotes_normalize(part.content, closing_quote)
            first = true

            value.each_line(chomp: true) do |line|
              if first
                first = false
              else
                breakable_return
              end

              text(line)
            end

            breakable_return if value.end_with?("\n")
          else
            visit(part)
          end
        end
        text(closing_quote)
      end
    end

    # `foo #{bar}`
    # ^^^^^^^^^^^^
    def visit_interpolated_x_string_node(node)
      if node.heredoc?
        visit_heredoc(node, node.parts)
      else
        group do
          text(node.opening)
          node.parts.each { |part| visit(part) }
          text(node.closing)
        end
      end
    end

    # it
    # ^^
    def visit_it_local_variable_read_node(_node)
      text("it")
    end

    # foo(bar: baz)
    #     ^^^^^^^^
    def visit_keyword_hash_node(node)
      elements = node.elements

      case stack[-2]&.type
      when :break_node, :next_node, :return_node
        visit_keyword_hash_node_layout(node) { |element| visit(element) }
      else
        if elements.any? { |element| element.value.is_a?(ImplicitNode) }
          visit_keyword_hash_node_layout(node) { |element| visit(element) }
        elsif elements.all? { |element|
                !element.is_a?(AssocNode) || element.operator_loc.nil? ||
                  element.key.is_a?(InterpolatedSymbolNode) ||
                  (
                    element.key.is_a?(SymbolNode) && (value = element.key.value) &&
                      value.match?(/^[_A-Za-z]/) &&
                      !value.end_with?("=")
                  )
              }
          visit_keyword_hash_node_layout(node) do |element|
            group { visit_assoc_node_label(element) }
          end
        else
          visit_keyword_hash_node_layout(node) do |element|
            group { visit_assoc_node_rocket(element) }
          end
        end
      end
    end

    # -> { it }
    # ^^^^^^^^^
    def visit_it_parameters_node(_node)
      raise "Visiting ItParametersNode is not supported."
    end

    # Visit a keyword hash node and yield out each plain association element for
    # formatting by the caller.
    private def visit_keyword_hash_node_layout(node)
      seplist(node.elements) do |element|
        if element.is_a?(AssocNode)
          yield element
        else
          visit(element)
        end
      end
    end

    # def foo(**bar); end
    #         ^^^^^
    #
    # def foo(**); end
    #         ^^
    def visit_keyword_rest_parameter_node(node)
      name = node.name

      text("**")
      text(name.name) if name
    end

    # -> {}
    def visit_lambda_node(node)
      parameters = node.parameters
      body = node.body
      closing_comments = node.closing_loc.comments

      group do
        text("->")
        visit(parameters) if parameters.is_a?(BlockParametersNode)

        if body || closing_comments.any?
          text(" ")
          if_break do
            text("do")
            node.opening_loc.comments.each { |comment| visit_comment(comment) }

            indent do
              if body
                breakable_space
                visit(body)
              end

              closing_comments.each do |comment|
                breakable_force

                if comment.is_a?(InlineComment)
                  text(comment.location.slice)
                else
                  trim
                  text(comment.location.slice.rstrip)
                end
              end
            end

            breakable_space
            text("end")
          end.if_flat do
            if body
              text("{ ")
              visit(body)
              text(" }")
            else
              text(" {}")
            end
          end
        else
          text(" {}")
        end
      end
    end

    # foo
    # ^^^
    def visit_local_variable_read_node(node)
      text(node.name.name)
    end

    # foo = 1
    # ^^^^^^^
    #
    # foo, bar = 1
    # ^^^  ^^^
    def visit_local_variable_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # foo += bar
    # ^^^^^^^^^^
    def visit_local_variable_operator_write_node(node)
      visit_write(node.binary_operator_loc, node.value) { text(node.name.name) }
    end

    # foo &&= bar
    # ^^^^^^^^^^^
    def visit_local_variable_and_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # foo ||= bar
    # ^^^^^^^^^^^
    def visit_local_variable_or_write_node(node)
      visit_write(node.operator_loc, node.value) { text(node.name.name) }
    end

    # foo, = bar
    # ^^^
    def visit_local_variable_target_node(node)
      text(node.name.name)
    end

    # if /foo/ then end
    #    ^^^^^
    def visit_match_last_line_node(node)
      visit_regular_expression_node_parts(
        node,
        [bare_string(node.send(:source), node.location.copy, node.content_loc)]
      )
    end

    # foo in bar
    # ^^^^^^^^^^
    def visit_match_predicate_node(node)
      pattern = node.pattern

      group do
        visit(node.value)
        text(" in")

        case pattern.type
        when :array_pattern_node, :hash_pattern_node, :find_pattern_node
          text(" ")
          visit(pattern)
        else
          indent do
            breakable_space
            visit(pattern)
          end
        end
      end
    end

    # foo => bar
    # ^^^^^^^^^^
    def visit_match_required_node(node)
      pattern = node.pattern

      group do
        visit(node.value)
        text(" =>")

        case pattern.type
        when :array_pattern_node, :hash_pattern_node, :find_pattern_node
          text(" ")
          visit(pattern)
        else
          indent do
            breakable_space
            visit(pattern)
          end
        end
      end
    end

    # /(?<foo>foo)/ =~ bar
    # ^^^^^^^^^^^^^^^^^^^^
    def visit_match_write_node(node)
      visit(node.call)
    end

    # A node that is missing from the syntax tree. This is only used in the
    # case of a syntax error. We'll format it as empty.
    def visit_missing_node(node)
    end

    # module Foo; end
    # ^^^^^^^^^^^^^^^
    def visit_module_node(node)
      module_keyword_loc = node.module_keyword_loc

      group do
        group do
          visit_location(module_keyword_loc)

          if module_keyword_loc.comments.any?
            indent do
              breakable_space
              visit(node.constant_path)
            end
          else
            text(" ")
            visit(node.constant_path)
          end
        end

        visit_body(node.body, node.end_keyword_loc.comments)
        breakable_force
        text("end")
      end
    end

    # foo, bar = baz
    # ^^^^^^^^
    def visit_multi_target_node(node)
      targets = [*node.lefts, *node.rest, *node.rights]
      implicit_rest = targets.pop if targets.last.is_a?(ImplicitRestNode)
      lparen_loc = node.lparen_loc

      group do
        if lparen_loc && node.rparen_loc
          visit_location(lparen_loc)
          indent do
            breakable_empty
            seplist(targets) { |target| visit(target) }
            visit(implicit_rest) if implicit_rest
          end
          breakable_empty
          text(")")
        else
          seplist(targets) { |target| visit(target) }
          visit(implicit_rest) if implicit_rest
        end
      end
    end

    # foo, bar = baz
    # ^^^^^^^^^^^^^^
    def visit_multi_write_node(node)
      targets = [*node.lefts, *node.rest, *node.rights]
      implicit_rest = targets.pop if targets.last.is_a?(ImplicitRestNode)
      lparen_loc = node.lparen_loc

      visit_write(node.operator_loc, node.value) do
        group do
          if lparen_loc && node.rparen_loc
            visit_location(lparen_loc)
            indent do
              breakable_empty
              seplist(targets) { |target| visit(target) }
              visit(implicit_rest) if implicit_rest
            end
            breakable_empty
            text(")")
          else
            seplist(targets) { |target| visit(target) }
            visit(implicit_rest) if implicit_rest
          end
        end
      end
    end

    # next
    # ^^^^
    #
    # next foo
    # ^^^^^^^^
    def visit_next_node(node)
      visit_jump("next", node.arguments)
    end

    # nil
    # ^^^
    def visit_nil_node(_node)
      text("nil")
    end

    # def foo(**nil); end
    #         ^^^^^
    def visit_no_keywords_parameter_node(node)
      group do
        visit_location(node.operator_loc)
        align(2) do
          breakable_empty
          text("nil")
        end
      end
    end

    # -> { _1 + _2 }
    # ^^^^^^^^^^^^^^
    def visit_numbered_parameters_node(_node)
      raise "Visiting NumberedParametersNode is not supported."
    end

    # $1
    # ^^
    def visit_numbered_reference_read_node(node)
      text(node.slice)
    end

    # def foo(bar: baz); end
    #         ^^^^^^^^
    def visit_optional_keyword_parameter_node(node)
      group do
        text("#{node.name.name}:")
        indent do
          breakable_space
          visit(node.value)
        end
      end
    end

    # def foo(bar = 1); end
    #         ^^^^^^^
    def visit_optional_parameter_node(node)
      group do
        text("#{node.name.name} ")
        visit_location(node.operator_loc)
        indent do
          breakable_space
          visit(node.value)
        end
      end
    end

    # a or b
    # ^^^^^^
    def visit_or_node(node)
      visit_binary(node.left, node.operator_loc, node.right)
    end

    # def foo(bar, *baz); end
    #         ^^^^^^^^^
    def visit_parameters_node(node)
      parameters = node.compact_child_nodes
      implicit_rest = parameters.pop if parameters.last.is_a?(ImplicitRestNode)

      align(0) do
        seplist(parameters) { |parameter| visit(parameter) }
        visit(implicit_rest) if implicit_rest
      end
    end

    # ()
    # ^^
    #
    # (1)
    # ^^^
    def visit_parentheses_node(node)
      group do
        visit_location(node.opening_loc)
        visit_body(node.body, node.closing_loc.comments, false)
        breakable_empty
        text(")")
      end
    end

    # foo => ^(bar)
    #        ^^^^^^
    def visit_pinned_expression_node(node)
      group do
        text("^")
        visit_location(node.lparen_loc)
        visit_body(node.expression, node.rparen_loc.comments, false)
        breakable_empty
        text(")")
      end
    end

    # foo = 1 and bar => ^foo
    #                    ^^^^
    def visit_pinned_variable_node(node)
      visit_prefix(node.operator_loc, node.variable)
    end

    # END {}
    def visit_post_execution_node(node)
      statements = node.statements
      closing_comments = node.closing_loc.comments

      group do
        text("END ")
        visit_location(node.opening_loc)

        if statements || closing_comments.any?
          indent do
            if statements
              breakable_space
              visit(statements)
            end

            closing_comments.each do |comment|
              breakable_empty
              text(comment.location.slice)
            end
          end

          breakable_space
        end

        text("}")
      end
    end

    # BEGIN {}
    def visit_pre_execution_node(node)
      statements = node.statements
      closing_comments = node.closing_loc.comments

      group do
        text("BEGIN ")
        visit_location(node.opening_loc)

        if statements || closing_comments.any?
          indent do
            if statements
              breakable_space
              visit(statements)
            end

            closing_comments.each do |comment|
              breakable_empty
              text(comment.location.slice)
            end
          end

          breakable_space
        end

        text("}")
      end
    end

    # The top-level program node.
    def visit_program_node(node)
      visit(node.statements)
      seplist(node.location.comments, -> { breakable_force }) do |comment|
        text(comment.location.slice.rstrip)
      end
      break_parent
    end

    # 0..5
    # ^^^^
    def visit_range_node(node)
      left = node.left
      right = node.right

      group do
        visit(left) if left
        visit_location(node.operator_loc)
        visit(right) if right
      end
    end

    # 1r
    # ^^
    def visit_rational_node(node)
      text(node.slice)
    end

    # redo
    # ^^^^
    def visit_redo_node(_node)
      text("redo")
    end

    # /foo/
    # ^^^^^
    def visit_regular_expression_node(node)
      visit_regular_expression_node_parts(
        node,
        [bare_string(node.send(:source), node.location.copy, node.content_loc)]
      )
    end

    # def foo(bar:); end
    #         ^^^^
    def visit_required_keyword_parameter_node(node)
      text("#{node.name.name}:")
    end

    # def foo(bar); end
    #         ^^^
    def visit_required_parameter_node(node)
      text(node.name.name)
    end

    # foo rescue bar
    # ^^^^^^^^^^^^^^
    def visit_rescue_modifier_node(node)
      group do
        text("begin")
        indent do
          breakable_force
          visit(node.expression)
        end
        breakable_force
        visit_location(node.keyword_loc)
        text(" StandardError")
        indent do
          breakable_force
          visit(node.rescue_expression)
        end
        breakable_force
        text("end")
      end
    end

    # begin; rescue; end
    #        ^^^^^^^
    def visit_rescue_node(node)
      exceptions = node.exceptions
      operator_loc = node.operator_loc
      reference = node.reference

      statements = node.statements
      subsequent = node.subsequent

      group do
        group do
          visit_location(node.keyword_loc)

          if exceptions.any?
            text(" ")
            align(7) { seplist(exceptions) { |exception| visit(exception) } }
          elsif reference.nil?
            text(" StandardError")
          end

          if reference
            text(" ")
            visit_location(operator_loc)

            if operator_loc.comments.any?
              indent do
                breakable_space
                visit(reference)
              end
            else
              text(" ")
              visit(reference)
            end
          end
        end

        if statements
          indent do
            breakable_force
            visit(statements)
          end
        end

        if subsequent
          breakable_force
          visit(subsequent)
        end
      end
    end

    # def foo(*bar); end
    #         ^^^^
    #
    # def foo(*); end
    #         ^
    def visit_rest_parameter_node(node)
      name = node.name

      if name
        group do
          visit_location(node.operator_loc)
          align(1) do
            breakable_empty
            text(node.name.name)
          end
        end
      else
        visit_location(node.operator_loc)
      end
    end

    # retry
    # ^^^^^
    def visit_retry_node(_node)
      text("retry")
    end

    # return
    # ^^^^^^
    #
    # return 1
    # ^^^^^^^^
    def visit_return_node(node)
      visit_jump("return", node.arguments)
    end

    # self
    # ^^^^
    def visit_self_node(_node)
      text("self")
    end

    # A shareable constant.
    def visit_shareable_constant_node(node)
      visit(node.write)
    end

    # class << self; end
    # ^^^^^^^^^^^^^^^^^^
    def visit_singleton_class_node(node)
      operator_loc = node.operator_loc

      group do
        group do
          text("class ")
          visit_location(operator_loc)

          if operator_loc.comments.any?
            indent do
              breakable_space
              visit(node.expression)
            end
          else
            text(" ")
            visit(node.expression)
          end
        end

        visit_body(node.body, node.end_keyword_loc.comments)
        breakable_force
        text("end")
      end
    end

    # __ENCODING__
    # ^^^^^^^^^^^^
    def visit_source_encoding_node(_node)
      text("__ENCODING__")
    end

    # __FILE__
    # ^^^^^^^^
    def visit_source_file_node(_node)
      text("__FILE__")
    end

    # __LINE__
    # ^^^^^^^^
    def visit_source_line_node(_node)
      text("__LINE__")
    end

    # foo(*bar)
    #     ^^^^
    #
    # def foo((bar, *baz)); end
    #               ^^^^
    #
    # def foo(*); bar(*); end
    #                 ^
    def visit_splat_node(node)
      expression = node.expression
      operator_loc = node.operator_loc

      if expression
        group do
          text("*")
          operator_loc.comments.each { |comment| visit_comment(comment) }

          align(1) { visit(expression) }
        end
      else
        text("*")
        operator_loc.comments.each { |comment| visit_comment(comment) }
      end
    end

    # A list of statements.
    def visit_statements_node(node)
      parent = stack[-2]

      previous_line = nil
      previous_access_control = false

      node.body.each do |statement|
        if previous_line.nil?
          visit(statement)
        elsif ((statement.location.start_line - previous_line) > 1) || previous_access_control ||
                access_control?(statement)
          breakable_force
          breakable_force
          visit(statement)
        elsif (statement.location.start_line != previous_line) ||
                !parent.is_a?(EmbeddedStatementsNode)
          breakable_force
          visit(statement)
        else
          text("; ")
          visit(statement)
        end

        previous_line = statement.heredoc_end_line
        previous_access_control = access_control?(statement)
      end
    end

    # "foo"
    # ^^^^^
    def visit_string_node(node)
      if node.heredoc?
        visit_heredoc(node, [node])
      else
        opening = node.opening
        content = node.content

        if !opening
          text(content)
        elsif opening == "?"
          if content.length == 1
            text(preferred_quote)
            text(content == preferred_quote ? "\\#{preferred_quote}" : content)
            text(preferred_quote)
          else
            text("?#{content}")
          end
        else
          visit_string_node_parts(node, [node])
        end
      end
    end

    # super(foo)
    # ^^^^^^^^^^
    def visit_super_node(node)
      arguments = [*node.arguments]
      block = node.block

      if block.is_a?(BlockArgumentNode)
        arguments << block
        block = nil
      end

      group do
        text("super")

        if node.lparen_loc && node.rparen_loc
          text("(")

          if arguments.any?
            indent do
              breakable_empty
              seplist(arguments) { |argument| visit(argument) }
            end
            breakable_empty
          end

          text(")")
        elsif arguments.any?
          text(" ")
          align(6) { seplist(arguments) { |argument| visit(argument) } }
        end

        if block
          text(" ")
          visit(block)
        end
      end
    end

    # :foo
    # ^^^^
    def visit_symbol_node(node)
      text(node.slice)
    end

    # true
    # ^^^^
    def visit_true_node(_node)
      text("true")
    end

    # undef foo
    # ^^^^^^^^^
    def visit_undef_node(node)
      group do
        text("undef ")
        align(6) do
          seplist(node.names) do |name|
            if name.is_a?(SymbolNode)
              text(name.value)

              if (comment = name.location.comments.first)
                visit_comment(comment)
              end
            else
              visit(name)
            end
          end
        end
      end
    end

    # unless foo; bar end
    # ^^^^^^^^^^^^^^^^^^^
    #
    # bar unless foo
    # ^^^^^^^^^^^^^^
    def visit_unless_node(node)
      statements = node.statements
      else_clause = node.else_clause

      if !statements || else_clause || contains_conditional?(statements.body.first)
        group do
          visit_unless_node_break(node)
          break_parent
        end
      elsif contains_write?(node.predicate) || contains_write?(statements)
        if node.end_keyword_loc
          group do
            visit_unless_node_break(node)
            break_parent
          end
        else
          group { visit_unless_node_flat(node) }
        end
      else
        group do
          if_break { visit_unless_node_break(node) }.if_flat do
            ensure_parentheses { visit_unless_node_flat(node) }
          end
        end
      end
    end

    # Visit an unless node in the break form.
    private def visit_unless_node_break(node)
      statements = node.statements
      else_clause = node.else_clause

      group do
        visit_location(node.keyword_loc)
        text(" ")
        align(3) { visit(node.predicate) }
      end

      if else_clause
        visit_body(statements, [], false)
        breakable_space
        visit(else_clause)
      else
        visit_body(statements, node.end_keyword_loc&.comments || [], false)
      end

      breakable_space
      text("end")
    end

    # Visit an unless node in the flat form.
    private def visit_unless_node_flat(node)
      visit(node.statements)
      text(" unless ")
      visit(node.predicate)
    end

    # until foo; bar end
    # ^^^^^^^^^^^^^^^^^
    #
    # bar until foo
    # ^^^^^^^^^^^^^
    def visit_until_node(node)
      statements = node.statements
      closing_loc = node.closing_loc

      if node.begin_modifier?
        group { visit_until_node_flat(node) }
      elsif statements.nil? || node.keyword_loc.comments.any? || closing_loc&.comments&.any?
        group do
          visit_until_node_break(node)
          break_parent
        end
      elsif contains_write?(node.predicate) || contains_write?(statements)
        if closing_loc
          group do
            visit_until_node_break(node)
            break_parent
          end
        else
          group { visit_until_node_flat(node) }
        end
      else
        group { if_break { visit_until_node_break(node) }.if_flat { visit_until_node_flat(node) } }
      end
    end

    # Visit an until node in the break form.
    private def visit_until_node_break(node)
      visit_location(node.keyword_loc)
      text(" ")
      align(6) { visit(node.predicate) }
      visit_body(node.statements, node.closing_loc&.comments || [], false)
      breakable_space
      text("end")
    end

    # Visit an until node in the flat form.
    private def visit_until_node_flat(node)
      ensure_parentheses do
        visit(node.statements)
        text(" until ")
        visit(node.predicate)
      end
    end

    # case foo; when bar; end
    #           ^^^^^^^^^^^^^
    def visit_when_node(node)
      conditions = node.conditions
      statements = node.statements

      group do
        group do
          text("when ")
          align(5) do
            seplist(conditions, -> { group { comma_breakable } }) { |condition| visit(condition) }

            # Very special case here. If you're inside of a when clause and the
            # last condition is an endless range, then you are forced to use the
            # "then" keyword to make it parse properly.
            last = conditions.last
            text(" then") if last.is_a?(RangeNode) && last.right.nil?
          end
        end

        if statements
          indent do
            breakable_force
            visit(statements)
          end
        end
      end
    end

    # while foo; bar end
    # ^^^^^^^^^^^^^^^^^^
    #
    # bar while foo
    # ^^^^^^^^^^^^^
    def visit_while_node(node)
      statements = node.statements
      closing_loc = node.closing_loc

      if node.begin_modifier?
        group { visit_while_node_flat(node) }
      elsif statements.nil? || node.keyword_loc.comments.any? || closing_loc&.comments&.any?
        group do
          visit_while_node_break(node)
          break_parent
        end
      elsif contains_write?(node.predicate) || contains_write?(statements)
        if closing_loc
          group do
            visit_while_node_break(node)
            break_parent
          end
        else
          group { visit_while_node_flat(node) }
        end
      else
        group { if_break { visit_while_node_break(node) }.if_flat { visit_while_node_flat(node) } }
      end
    end

    # Visit a while node in the flat form.
    private def visit_while_node_flat(node)
      ensure_parentheses do
        visit(node.statements)
        text(" while ")
        visit(node.predicate)
      end
    end

    # Visit a while node in the break form.
    private def visit_while_node_break(node)
      visit_location(node.keyword_loc)
      text(" ")
      align(6) { visit(node.predicate) }
      visit_body(node.statements, node.closing_loc&.comments || [], false)
      breakable_space
      text("end")
    end

    # `foo`
    # ^^^^^
    def visit_x_string_node(node)
      if node.heredoc?
        visit_heredoc(node, [node])
      else
        text("`#{node.content}`")
      end
    end

    # yield
    # ^^^^^
    #
    # yield 1
    # ^^^^^^^
    def visit_yield_node(node)
      arguments = node.arguments

      if arguments.nil?
        text("yield")
      else
        lparen_loc = node.lparen_loc
        rparen_loc = node.rparen_loc

        group do
          text("yield")

          if lparen_loc
            visit_location(lparen_loc)
          else
            if_break { text("(") }.if_flat { text(" ") }
          end

          indent do
            breakable_empty
            visit(arguments)
          end
          breakable_empty

          if rparen_loc
            visit_location(rparen_loc)
          else
            if_break { text(")") }
          end
        end
      end
    end

    private

    # --------------------------------------------------------------------------
    # Helper methods
    # --------------------------------------------------------------------------

    # Returns whether or not the given statement is an access control statement.
    # Truthfully, we can't actually tell this for sure without performing method
    # lookup, but we assume none of these methods are overridden.
    def access_control?(statement)
      statement.is_a?(CallNode) && statement.variable_call? &&
        %i[private protected public].include?(statement.name)
    end

    # There are times when it is useful to create string nodes so that
    # non-interpolated nodes can be formatted as if they were their interpolated
    # counterparts with a single part.
    def bare_string(source, location, content_loc)
      StringNode.new(source, 0, location, 0, nil, content_loc, 0, "")
    end

    # (source, node_id, location, flags, opening_loc, content_loc, closing_loc, unescaped)

    # True if the given node contains a conditional expression.
    def contains_conditional?(node)
      case node.type
      when :if_node, :unless_node
        true
      else
        false
      end
    end

    # True if the given node contains a write expression.
    def contains_write?(node)
      case node.type
      when :call_and_write_node, :call_or_write_node, :call_operator_write_node,
           :class_variable_write_node, :class_variable_and_write_node,
           :class_variable_or_write_node, :class_variable_operator_write_node, :constant_write_node,
           :constant_and_write_node, :constant_or_write_node, :constant_operator_write_node,
           :constant_path_write_node, :constant_path_and_write_node, :constant_path_or_write_node,
           :constant_path_operator_write_node, :global_variable_write_node,
           :global_variable_and_write_node, :global_variable_or_write_node,
           :global_variable_operator_write_node, :instance_variable_write_node,
           :instance_variable_and_write_node, :instance_variable_or_write_node,
           :instance_variable_operator_write_node, :local_variable_write_node,
           :local_variable_and_write_node, :local_variable_or_write_node,
           :local_variable_operator_write_node, :multi_write_node
        true
      when :class_node, :module_node, :singleton_class_node
        false
      else
        node.compact_child_nodes.any? { |child| contains_write?(child) }
      end
    end

    # If you have a modifier statement (for instance a modifier if statement or
    # a modifier while loop) there are times when you need to wrap the entire
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
    # second example will result in an empty hash because the if statement
    # applies to the entire assignment.
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
    def ensure_parentheses
      case stack[-2]&.type
      when :arguments_node, :assoc_node, :call_node, :call_and_write_node, :call_or_write_node,
           :call_operator_write_node, :class_variable_write_node, :class_variable_and_write_node,
           :class_variable_or_write_node, :class_variable_operator_write_node, :constant_write_node,
           :constant_and_write_node, :constant_or_write_node, :constant_operator_write_node,
           :constant_path_write_node, :constant_path_and_write_node, :constant_path_or_write_node,
           :constant_path_operator_write_node, :global_variable_write_node,
           :global_variable_and_write_node, :global_variable_or_write_node,
           :global_variable_operator_write_node, :instance_variable_write_node,
           :instance_variable_and_write_node, :instance_variable_or_write_node,
           :instance_variable_operator_write_node, :local_variable_write_node,
           :local_variable_and_write_node, :local_variable_or_write_node,
           :local_variable_operator_write_node, :multi_write_node
        text("(")
        yield
        text(")")
      else
        yield
      end
    end

    # Returns whether or not the given node should be indented when it is
    # printed as the value of a write expression.
    def indent_write?(node)
      case node.type
      when :array_node
        node.opening_loc.nil?
      when :hash_node, :lambda_node
        false
      when :string_node, :x_string_node, :interpolated_string_node, :interpolated_x_string_node
        !node.heredoc?
      when :call_node
        node.receiver.nil? || indent_write?(node.receiver)
      when :interpolated_symbol_node
        node.opening_loc.nil? || !node.opening.start_with?("%s")
      else
        true
      end
    end

    # If there is some part of the string that matches an escape sequence or
    # that contains the interpolation pattern ("#{"), then we are locked into
    # whichever quote the user chose. (If they chose single quotes, then double
    # quoting would activate the escape sequence, and if they chose double
    # quotes, then single quotes would deactivate it.)
    def quotes_locked?(parts)
      parts.any? do |node|
        !node.is_a?(StringNode) || node.content.match?(/\\|#[@${]|#{preferred_quote}/)
      end
    end

    # Find the matching closing quote for the given opening quote.
    def quotes_matching(quote)
      case quote
      when "("
        ")"
      when "["
        "]"
      when "{"
        "}"
      when "<"
        ">"
      else
        quote
      end
    end

    # Escape and unescape single and double quotes as needed to be able to
    # enclose +content+ with +enclosing+.
    def quotes_normalize(content, enclosing)
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

    # --------------------------------------------------------------------------
    # Visit helpers
    # --------------------------------------------------------------------------

    # Visit a node and format it, including any comments that are found around
    # it that are attached to its location.
    def visit(node)
      stack << node

      ignore = false
      previous_line = nil

      node.location.leading_comments.each do |comment|
        slice = comment.slice

        if previous_line
          if (comment.location.start_line - previous_line) > 1
            breakable_force
            breakable_force
          else
            breakable_force
          end
        end

        if comment.is_a?(InlineComment)
          text(slice)
          previous_line = comment.location.end_line
        else
          trim
          text(slice.rstrip)
          previous_line = comment.location.end_line - 1
        end

        ignore ||= slice.include?("stree-ignore")
      end

      if previous_line
        if (node.location.start_line - previous_line) > 1
          breakable_force
          breakable_force
        else
          breakable_force
        end
      end

      doc =
        if ignore
          # If the node has a stree-ignore comment right before it, then we're
          # going to just print out the node as it was seen in the source.
          align(0) do
            slice = node.slice
            seplist(slice.each_line(chomp: true), -> { breakable_return }) do |line|
              text(line)
            end
            breakable_return if slice.end_with?("\n")
          end
        else
          node.accept(self)
        end

      node.location.trailing_comments.each { |comment| visit_comment(comment) }

      stack.pop
      doc
    end

    # Visit a binary expression, and format it with the given left and right
    # nodes, and the given operator location.
    def visit_binary(left, operator_loc, right)
      group do
        visit(left)
        text(" ")
        visit_location(operator_loc)
        indent do
          breakable_space
          visit(right)
        end
      end
    end

    # Visit the body of a node, and format it with the given comments.
    def visit_body(body, comments, force_break = true)
      break_parent if force_break && (body || comments.any?)

      indent do
        if body
          breakable_empty if !body.is_a?(BeginNode) || !body.statements.nil?
          visit(body)
        end

        comments.each do |comment|
          if comment.is_a?(InlineComment)
            breakable_force
            text(comment.location.slice)
          else
            breakable_force
            trim
            text(comment.location.slice.rstrip)
          end
        end
      end
    end

    # Visit a comment and print it out.
    def visit_comment(comment)
      if !comment.is_a?(InlineComment)
        breakable_force
        trim
        text(comment.location.slice.rstrip)
        breakable_force
      elsif comment.trailing?
        line_suffix(COMMENT_PRIORITY) do
          text(" ")
          text(comment.location.slice)
          break_parent
        end
      else
        breakable_space
        text(comment.location.slice)
        break_parent
      end
    end

    # Visit a set of elements within a collection, along with the comments that
    # may be present within them.
    def visit_elements(elements, comments)
      indent do
        if elements.any?
          breakable_empty
          seplist(elements) { |element| visit(element) }
          if_break { text(",") } if trailing_comma
        end

        comments.each do |comment|
          breakable_force
          text(comment.location.slice)
        end
      end
    end

    # Visit a set of elements within a collection, along with the comments that
    # may be present within them. Additionally add a space before the start and
    # after the end of the collection.
    def visit_elements_spaced(elements, comments)
      indent do
        if elements.any?
          breakable_space
          seplist(elements) { |element| visit(element) }
        end

        comments.each do |comment|
          breakable_force
          text(comment.slice)
        end
      end
    end

    # Visit a heredoc node, and format it with the given parts.
    def visit_heredoc(node, parts)
      # If the heredoc is indented, then we're going to need to reintroduce the
      # indentation to the parts of the heredoc.
      indent = parts.first.is_a?(StringNode) ? "" : parts.first.location.start_line_slice
      opening = node.opening

      if opening[2] == "~"
        parts.each do |part|
          if part.is_a?(StringNode) && !part.content.start_with?("\n")
            indent = part.content[/\A[ \t]*/].delete_prefix(part.unescaped[/\A[ \t]*/])
            break
          end
        end
      end

      group do
        text(opening)
        line_suffix(HEREDOC_PRIORITY) do
          group do
            target << BREAKABLE_RETURN

            previous_newline = true
            parts.each do |part|
              case part.type
              when :string_node, :x_string_node
                value = part.content
                seplist(value.each_line(chomp: true), -> { target << BREAKABLE_RETURN }) do |line|
                  text(line)
                end

                if (previous_newline = value.end_with?("\n"))
                  target << BREAKABLE_RETURN
                end
              else
                text(indent) if previous_newline
                visit(part)
                previous_newline = false
              end
            end

            text(node.closing.chomp)
          end
        end
      end
    end

    # Visit a jump expression, which consists of a keyword followed by an
    # optional set of arguments.
    def visit_jump(keyword, arguments)
      if !arguments
        text(keyword)
      elsif arguments.arguments.length == 1
        argument = arguments.arguments.first

        case argument.type
        when :parentheses_node
          body = argument.body

          if body.is_a?(StatementsNode) && body.body.length == 1
            case (first = body.body.first).type
            when :class_variable_read_node, :constant_read_node, :false_node, :float_node,
                 :global_variable_read_node, :imaginary_node, :instance_variable_read_node,
                 :integer_node, :local_variable_read_node, :nil_node, :rational_node, :self_node,
                 :true_node
              text("#{keyword} ")
              visit(first)
            when :array_node
              if first.elements.length > 1
                group do
                  text(keyword)
                  if_break { text(" [") }.if_flat { text(" ") }

                  indent do
                    breakable_empty
                    seplist(first.elements) { |element| visit(element) }
                  end

                  if_break do
                    breakable_empty
                    text("]")
                  end
                end
              else
                text("#{keyword} ")
                visit(first)
              end
            else
              group do
                text(keyword)
                visit(argument)
              end
            end
          else
            group do
              text(keyword)
              visit(argument)
            end
          end
        when :class_variable_read_node, :constant_read_node, :false_node, :float_node,
             :global_variable_read_node, :imaginary_node, :instance_variable_read_node,
             :integer_node, :local_variable_read_node, :nil_node, :rational_node, :self_node,
             :true_node
          text("#{keyword} ")
          visit(argument)
        when :array_node
          if argument.elements.length > 1
            group do
              text(keyword)
              if_break { text(" [") }.if_flat { text(" ") }

              indent do
                breakable_empty
                seplist(argument.elements) { |element| visit(element) }
              end

              if_break do
                breakable_empty
                text("]")
              end
            end
          else
            text("#{keyword} ")
            visit(argument)
          end
        else
          group do
            text(keyword)
            if_break { text("(") }.if_flat { text(" ") }

            indent do
              breakable_empty
              visit(argument)
            end

            if_break do
              breakable_empty
              text(")")
            end
          end
        end
      else
        group do
          text(keyword)
          if_break { text(" [") }.if_flat { text(" ") }

          indent do
            breakable_empty
            visit(arguments)
          end

          if_break do
            breakable_empty
            text("]")
          end
        end
      end
    end

    # Print out a slice of the given location, and handle any attached trailing
    # comments that may be present.
    def visit_location(location, value = location.slice)
      location.leading_comments.each do |comment|
        if comment.is_a?(InlineComment)
          text(comment.location.slice)
        else
          breakable_force
          trim
          text(comment.location.slice.rstrip)
        end
        breakable_force
      end

      text(value)
      location.trailing_comments.each { |comment| visit_comment(comment) }
    end

    # Visit a prefix expression, which consists of a single operator prefixing
    # a nested expression.
    def visit_prefix(operator_loc, value)
      if value
        group do
          visit_location(operator_loc)
          align(operator_loc.length) { visit(value) }
        end
      else
        visit_location(operator_loc)
      end
    end

    # Visit the parts of a regular expression-like node.
    def visit_regular_expression_node_parts(node, parts)
      # If the first part of this regex is plain string content, we have a space
      # or an =, and we're contained within a command or command_call node, then
      # we want to use braces because otherwise we could end up with an
      # ambiguous operator, e.g. foo / bar/ or foo /=bar/
      ambiguous =
        (
          (part = parts.first) && part.is_a?(StringNode) && part.content.start_with?(" ", "=") &&
            stack[0...-1].reverse_each.any? do |parent|
              parent.is_a?(CallNode) && parent.arguments && parent.opening_loc.nil?
            end
        )

      braces =
        (ambiguous || parts.any? { |part| part.is_a?(StringNode) && part.content.include?("/") })

      if braces && parts.any? { |part| part.is_a?(StringNode) && part.content.match?(/[{}]/) }
        group do
          text(node.opening)
          parts.each { |part| visit(part) }
          text(node.closing)
        end
      elsif braces
        group do
          text("%r{")

          parts.each do |part|
            if part.is_a?(StringNode)
              seplist(part.content.each_line(chomp: true), -> { breakable_return }) do |line|
                text(line.gsub(%r{(?<!\\)\\/}, "/"))
              end
            else
              visit(part)
            end
          end

          text("}")
          text(node.closing[1..])
        end
      else
        group do
          text("/")
          parts.each { |part| visit(part) }
          text("/")
          text(node.closing[1..])
        end
      end
    end

    # Visit the parts of a string-like node.
    def visit_string_node_parts(node, parts)
      # First, if there is no opening quote, then this is either a part of a
      # %w/%W list or it is a string literal representing string concatenation.
      # Either way, we'll bail out and just print the string as is.
      opening = node.opening
      return group { parts.each { |part| visit(part) } } if opening.nil?

      # If we get here, then we're going to need to add quotes to the string. In
      # this case we'll determine which quotes to use. If it's possible for us
      # to switch the quotes, we'll use the preferred quote of the formatter and
      # re-escape the inner quotes. Otherwise, we'll use the same quotes as the
      # source.
      closing = node.closing
      opening_quote, closing_quote =
        if !quotes_locked?(parts)
          [preferred_quote, preferred_quote]
        elsif opening.start_with?("%")
          [opening, quotes_matching(opening[/%[qQ]?(.)/, 1])]
        else
          [opening, closing]
        end

      # Here we'll actually build the doc tree. This will involve a group that
      # is bound by the opening and closing quotes, and then we'll visit each
      # part of the string.
      group do
        text(opening_quote)

        parts.each do |part|
          if part.is_a?(StringNode)
            value = quotes_normalize(part.content, closing_quote)

            first = true
            value.each_line(chomp: true) do |line|
              if first
                first = false
              else
                breakable_return
              end

              text(line)
            end

            breakable_return if value.end_with?("\n")
          else
            visit(part)
          end
        end

        text(closing_quote)
      end
    end

    # Visit a write expression, and format it with the given operator and value.
    def visit_write(operator_loc, value)
      group do
        yield
        text(" ")
        visit_location(operator_loc)

        if operator_loc.trailing_comments.any? || indent_write?(value)
          indent do
            breakable_space
            visit(value)
          end
        else
          text(" ")
          visit(value)
        end
      end
    end

    # --------------------------------------------------------------------------
    # Printing algorithm
    # --------------------------------------------------------------------------

    # Flushes all of the generated print tree onto the output buffer.
    def flush
      # First, get the root group, since we placed one at the top to begin with.
      doc = groups.first

      # This represents how far along the current line we are. It gets reset
      # back to 0 when we encounter a newline.
      position = 0

      # This is our command stack. A command consists of a triplet of an
      # indentation level, the mode (break or flat), and a doc node.
      commands = [[0, MODE_BREAK, doc]]

      # This is a small optimization boolean. It keeps track of whether or not
      # when we hit a group node we should check if it fits on the same line.
      should_remeasure = false

      # This is a separate command stack that includes the same kind of triplets
      # as the commands variable. It is used to keep track of things that should
      # go at the end of printed lines once the other doc nodes are accounted for.
      # Typically this is used to implement comments.
      line_suffixes = []

      # This is a special sort used to order the line suffixes by both the
      # priority set on the line suffix and the index it was in the original
      # array.
      line_suffix_sort = ->(line_suffix) do
        [-line_suffix.last.priority, -line_suffixes.index(line_suffix)]
      end

      # This is a linear stack instead of a mutually recursive call defined on
      # the individual doc nodes for efficiency.
      while (indent, mode, doc = commands.pop)
        case doc.type
        when :string
          buffer << doc
          position += doc.length
        when :group
          if mode == MODE_FLAT && !should_remeasure
            next_mode = doc.break ? MODE_BREAK : MODE_FLAT
            commands.concat(doc.contents.reverse.map { |part| [indent, next_mode, part] })
          else
            should_remeasure = false

            if doc.break
              commands.concat(doc.contents.reverse.map { |part| [indent, MODE_BREAK, part] })
            else
              next_commands = doc.contents.reverse.map { |part| [indent, MODE_FLAT, part] }

              if fits?(next_commands, commands, print_width - position)
                commands.concat(next_commands)
              else
                next_commands.each { |command| command[1] = MODE_BREAK }
                commands.concat(next_commands)
              end
            end
          end
        when :breakable
          if mode == MODE_FLAT
            if doc.force
              # This line was forced into the output even if we were in flat mode,
              # so we need to tell the next group that no matter what, it needs to
              # remeasure because the previous measurement didn't accurately
              # capture the entire expression (this is necessary for nested
              # groups).
              should_remeasure = true
            else
              buffer << doc.separator
              position += doc.width
              next
            end
          end

          # If there are any commands in the line suffix buffer, then we're going
          # to flush them now, as we are about to add a newline.
          if line_suffixes.any?
            commands << [indent, mode, doc]

            line_suffixes
              .sort_by(&line_suffix_sort)
              .each do |(indent, mode, doc)|
                commands += doc.contents.reverse.map { |part| [indent, mode, part] }
              end

            line_suffixes.clear
            next
          end

          if !doc.indent
            buffer << "\n"
            position = 0
          else
            position -= trim!(buffer)
            buffer << "\n"
            buffer << " " * indent
            position = indent
          end
        when :indent
          next_indent = indent + 2
          commands.concat(doc.contents.reverse.map { |part| [next_indent, mode, part] })
        when :align
          next_indent = indent + doc.indent
          commands.concat(doc.contents.reverse.map { |part| [next_indent, mode, part] })
        when :trim
          position -= trim!(buffer)
        when :if_break
          if mode == MODE_BREAK && doc.break_contents.any?
            commands.concat(doc.break_contents.reverse.map { |part| [indent, mode, part] })
          elsif mode == MODE_FLAT && doc.flat_contents.any?
            commands.concat(doc.flat_contents.reverse.map { |part| [indent, mode, part] })
          end
        when :line_suffix
          line_suffixes << [indent, mode, doc]
        when :break_parent
        # do nothing
        else
          # Special case where the user has defined some way to get an extra doc
          # node that we don't explicitly support into the list. In this case
          # we're going to assume it's 0-width and just append it to the output
          # buffer.
          #
          # This is useful behavior for putting marker nodes into the list so that
          # you can know how things are getting mapped before they get printed.
          buffer << doc
        end

        if commands.empty? && line_suffixes.any?
          line_suffixes
            .sort_by(&line_suffix_sort)
            .each do |(indent, mode, doc)|
              commands.concat(doc.contents.reverse.map { |part| [indent, mode, part] })
            end

          line_suffixes.clear
        end
      end
    end

    # This method returns a boolean as to whether or not the remaining commands
    # fit onto the remaining space on the current line. If we finish printing
    # all of the commands or if we hit a newline, then we return true. Otherwise
    # if we continue printing past the remaining space, we return false.
    def fits?(next_commands, rest_commands, remaining)
      # This is the index in the remaining commands that we've handled so far.
      # We reverse through the commands and add them to the stack if we've run
      # out of nodes to handle.
      rest_index = rest_commands.length

      # This is our stack of commands, very similar to the commands list in the
      # print method.
      commands = [*next_commands]

      # This is our output buffer, really only necessary to keep track of
      # because we could encounter a Trim doc node that would actually add
      # remaining space.
      fit_buffer = []

      while remaining >= 0
        if commands.empty?
          return true if rest_index == 0

          rest_index -= 1
          commands << rest_commands[rest_index]
          next
        end

        indent, mode, doc = commands.pop

        case doc.type
        when :string
          fit_buffer << doc
          remaining -= doc.length
        when :group
          next_mode = doc.break ? MODE_BREAK : mode
          commands += doc.contents.reverse.map { |part| [indent, next_mode, part] }
        when :breakable
          if mode == MODE_FLAT && !doc.force
            fit_buffer << doc.separator
            remaining -= doc.width
            next
          end

          return true
        when :indent
          next_indent = indent + 2
          commands += doc.contents.reverse.map { |part| [next_indent, mode, part] }
        when :align
          next_indent = indent + doc.indent
          commands += doc.contents.reverse.map { |part| [next_indent, mode, part] }
        when :trim
          remaining += trim!(fit_buffer)
        when :if_break
          if mode == MODE_BREAK && doc.break_contents.any?
            commands += doc.break_contents.reverse.map { |part| [indent, mode, part] }
          elsif mode == MODE_FLAT && doc.flat_contents.any?
            commands += doc.flat_contents.reverse.map { |part| [indent, mode, part] }
          end
        end
      end

      false
    end

    def trim!(buffer)
      return 0 if buffer.empty?

      trimmed = 0

      while buffer.any? && buffer.last.is_a?(String) && buffer.last.match?(/\A[\t ]*\z/)
        trimmed += buffer.pop.length
      end

      if buffer.any? && buffer.last.is_a?(String) && !buffer.last.frozen?
        length = buffer.last.length
        buffer.last.gsub!(/[\t ]*\z/, "")
        trimmed += length - buffer.last.length
      end

      trimmed
    end

    # --------------------------------------------------------------------------
    # Helper node builders
    # --------------------------------------------------------------------------

    # This method calculates the position of the text relative to the current
    # indentation level when the doc has been printed. It's useful for
    # determining how to align text to doc nodes that are already built into the
    # tree.
    def last_position(node)
      queue = [node]
      width = 0

      while (doc = queue.shift)
        case doc.type
        when :string
          width += doc.length
        when :group, :indent, :align
          queue = doc.contents + queue
        when :breakable
          width = 0
        when :if_break
          queue = doc.break_contents + queue
        end
      end

      width
    end

    # This method will remove any breakables from the list of contents so that
    # no newlines are present in the output. If a newline is being forced into
    # the output, the replace value will be used.
    def remove_breaks(node, replace = "; ")
      queue = [node]

      while (doc = queue.shift)
        case doc.type
        when :align, :indent
          doc.contents.map! { |child| remove_breaks_with(child, replace) }
          queue.concat(doc.contents)
        when :group
          doc.unbreak!
          doc.contents.map! { |child| remove_breaks_with(child, replace) }
          queue.concat(doc.contents)
        when :if_break
          doc.flat_contents.map! { |child| remove_breaks_with(child, replace) }
          queue.concat(doc.flat_contents)
        end
      end
    end

    # Remove breaks from a subtree with the given replacement string.
    def remove_breaks_with(doc, replace)
      case doc.type
      when :breakable
        doc.force ? replace : doc.separator
      when :if_break
        Align.new(0, doc.flat_contents)
      else
        doc
      end
    end

    # Adds a separated list.
    # The list is separated by comma with breakable space, by default.
    #
    # #seplist iterates the +list+ using +each+.
    # It yields each object to the block given for #seplist.
    # The procedure +separator_proc+ is called between each yields.
    #
    # If the iteration is zero times, +separator_proc+ is not called at all.
    #
    # If +separator_proc+ is nil or not given,
    # +lambda { comma_breakable }+ is used.
    #
    # For example, following 3 code fragments has similar effect.
    #
    #   q.seplist([1,2,3]) {|v| xxx v }
    #
    #   q.seplist([1,2,3], lambda { q.comma_breakable }, :each) {|v| xxx v }
    #
    #   xxx 1
    #   q.comma_breakable
    #   xxx 2
    #   q.comma_breakable
    #   xxx 3
    def seplist(list, sep = nil)
      first = true

      list.each do |v|
        if first
          first = false
        elsif sep
          sep.call
        else
          comma_breakable
        end

        yield(v)
      end
    end

    # --------------------------------------------------------------------------
    # Markers node builders
    # --------------------------------------------------------------------------

    # This says "you can break a line here if necessary", and a +width+\-column
    # text +separator+ is inserted if a line is not broken at the point.
    #
    # If +separator+ is not specified, ' ' is used.
    #
    # If +width+ is not specified, +separator.length+ is used. You will have to
    # specify this when +separator+ is a multibyte character, for example.
    #
    # By default, if the surrounding group is broken and a newline is inserted,
    # the printer will indent the subsequent line up to the current level of
    # indentation. You can disable this behavior with the +indent+ argument if
    # that's not desired (rare).
    #
    # By default, when you insert a Breakable into the print tree, it only
    # breaks the surrounding group when the group's contents cannot fit onto the
    # remaining space of the current line. You can force it to break the
    # surrounding group instead if you always want the newline with the +force+
    # argument.
    #
    # There are a few circumstances where you'll want to force the newline into
    # the output but no insert a break parent (because you don't want to
    # necessarily force the groups to break unless they need to). In this case
    # you can pass `force: :skip_break_parent` to this method and it will not
    # insert a break parent.

    # The vast majority of breakable calls you receive while formatting are a
    # space in flat mode and a newline in break mode. Since this is so common,
    # we have a method here to skip past unnecessary calculation.
    def breakable_space
      target << BREAKABLE_SPACE
    end

    # Another very common breakable call you receive while formatting is an
    # empty string in flat mode and a newline in break mode. Similar to
    # breakable_space, this is here for avoid unnecessary calculation.
    def breakable_empty
      target << BREAKABLE_EMPTY
    end

    # The final of the very common breakable calls you receive while formatting
    # is the normal breakable space but with the addition of the break_parent.
    def breakable_force
      target << BREAKABLE_FORCE
      break_parent
    end

    # This is the same shortcut as breakable_force, except that it doesn't
    # indent the next line. This is necessary if you're trying to preserve some
    # custom formatting like a multi-line string.
    def breakable_return
      target << BREAKABLE_RETURN
      break_parent
    end

    # This inserts a BreakParent node into the print tree which forces the
    # surrounding and all parent group nodes to break.
    def break_parent
      doc = BREAK_PARENT
      target << doc

      groups.reverse_each do |group|
        break if group.break
        group.break!
      end
    end

    # A convenience method which is same as follows:
    #
    #   text(",")
    #   breakable
    def comma_breakable
      text(",")
      breakable_space
    end

    # This inserts a Trim node into the print tree which, when printed, will
    # clear all whitespace at the end of the output buffer. This is useful for
    # the rare case where you need to delete printed indentation and force the
    # next node to start at the beginning of the line.
    def trim
      target << TRIM
    end

    # --------------------------------------------------------------------------
    # Container node builders
    # --------------------------------------------------------------------------

    # Increases left margin after newline with +indent+ for line breaks added in
    # the block.
    def align(indent)
      contents = []
      doc = Align.new(indent, contents)
      target << doc

      with_target(contents) { yield }
      doc
    end

    # Groups line break hints added in the block. The line break hints are all
    # to be used or not.
    #
    # If +indent+ is specified, the method call is regarded as nested by
    # align(indent) { ... }.
    #
    # If +open_object+ is specified, <tt>text(open_object, open_width)</tt> is
    # called before grouping. If +close_object+ is specified,
    # <tt>text(close_object, close_width)</tt> is called after grouping.
    def group
      contents = []
      doc = Group.new(contents)

      groups << doc
      target << doc

      with_target(contents) { yield }
      groups.pop

      doc
    end

    # Group if the predicate is true, otherwise just yield the block.
    def group_if(predicate)
      if predicate
        group { yield }
      else
        yield
      end
    end

    # A small DSL-like object used for specifying the alternative contents to be
    # printed if the surrounding group doesn't break for an IfBreak node.
    class IfBreakBuilder
      attr_reader :q, :flat_contents

      def initialize(q, flat_contents)
        @q = q
        @flat_contents = flat_contents
      end

      def if_flat
        q.with_target(flat_contents) { yield }
      end
    end

    # When we already know that groups are broken, we don't actually need to
    # track the flat versions of the contents. So this builder version is
    # effectively a no-op, but we need it to maintain the same API. The only
    # thing this can impact is that if there's a forced break in the flat
    # contents, then we need to propagate that break up the whole tree.
    class IfFlatIgnore
      attr_reader :q

      def initialize(q)
        @q = q
      end

      def if_flat
        contents = []
        group = Group.new(contents)

        q.with_target(contents) { yield }
        q.break_parent if group.break
      end
    end

    # Inserts an IfBreak node with the contents of the block being added to its
    # list of nodes that should be printed if the surrounding node breaks. If it
    # doesn't, then you can specify the contents to be printed with the #if_flat
    # method used on the return object from this method. For example,
    #
    #     q.if_break { q.text('do') }.if_flat { q.text('{') }
    #
    # In the example above, if the surrounding group is broken it will print
    # 'do' and if it is not it will print '{'.
    def if_break
      break_contents = []
      flat_contents = []

      doc = IfBreak.new(break_contents, flat_contents)
      target << doc

      with_target(break_contents) { yield }

      if groups.last.break
        IfFlatIgnore.new(self)
      else
        IfBreakBuilder.new(self, flat_contents)
      end
    end

    # This is similar to if_break in that it also inserts an IfBreak node into
    # the print tree, however it's starting from the flat contents, and cannot
    # be used to build the break contents.
    def if_flat
      if groups.last.break
        contents = []
        group = Group.new(contents)

        with_target(contents) { yield }
        break_parent if group.break
      else
        flat_contents = []
        doc = IfBreak.new(break_contents, flat_contents)
        target << doc

        with_target(flat_contents) { yield }
        doc
      end
    end

    # Very similar to the #nest method, this indents the nested content by one
    # level by inserting an Indent node into the print tree. The contents of the
    # node are determined by the block.
    def indent
      contents = []
      doc = Indent.new(contents)
      target << doc

      with_target(contents) { yield }
      doc
    end

    # Inserts a LineSuffix node into the print tree. The contents of the node
    # are determined by the block.
    def line_suffix(priority)
      contents = []
      doc = LineSuffix.new(priority, contents)
      target << doc

      with_target(contents) { yield }
      doc
    end

    # Push a value onto the output target.
    def text(value)
      target << value
    end
  end
end
