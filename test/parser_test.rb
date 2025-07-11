# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class ParserTest < Minitest::Test
    def test_parses_ripper_methods
      # First, get a list of all of the dispatched events from ripper.
      events = Ripper::EVENTS

      # Next, subtract all of the events that we have explicitly defined.
      events -=
        Parser.private_instance_methods(false).grep(/^on_(\w+)/) { $1.to_sym }

      # Next, subtract the list of events that we purposefully skipped.
      events -= %i[
        arg_ambiguous
        assoclist_from_args
        ignored_nl
        ignored_sp
        magic_comment
        nl
        nokw_param
        operator_ambiguous
        semicolon
        sp
        words_sep
      ]

      # Finally, assert that we have no remaining events.
      assert_empty(events)
    end

    def test_errors_on_missing_token_with_location
      error = assert_raises(Parser::ParseError) { SyntaxTree.parse("f+\"foo") }
      assert_equal(3, error.column)
    end

    def test_errors_on_missing_end_with_location
      error = assert_raises(Parser::ParseError) { SyntaxTree.parse("foo do 1") }
      assert_equal(4, error.column)
    end

    def test_errors_on_missing_regexp_ending
      error =
        assert_raises(Parser::ParseError) { SyntaxTree.parse("a =~ /foo") }

      assert_equal(6, error.column)
    end

    def test_errors_on_missing_token_without_location
      assert_raises(Parser::ParseError) { SyntaxTree.parse(":\"foo") }
    end

    def test_handles_strings_with_non_terminated_embedded_expressions
      assert_raises(Parser::ParseError) { SyntaxTree.parse('"#{"') }
    end

    def test_errors_on_else_missing_two_ends
      assert_raises(Parser::ParseError) { SyntaxTree.parse(<<~RUBY) }
        def foo
          if something
          else
            call do
        end
      RUBY
    end

    def test_does_not_choke_on_invalid_characters_in_source_string
      SyntaxTree.parse(<<~RUBY)
        # comment
        # comment
        __END__
        \xC5
      RUBY
    end

    def test_lambda_vars_with_parameters_location
      tree = SyntaxTree.parse(<<~RUBY)
        # comment
        # comment
        ->(_i; a) { a }
      RUBY

      local_location =
        tree.statements.body.last.params.contents.locals.first.location

      assert_equal(3, local_location.start_line)
      assert_equal(3, local_location.end_line)
      assert_equal(7, local_location.start_column)
      assert_equal(8, local_location.end_column)
    end

    def test_lambda_vars_location
      tree = SyntaxTree.parse(<<~RUBY)
        # comment
        # comment
        ->(; a) { a }
      RUBY

      local_location =
        tree.statements.body.last.params.contents.locals.first.location

      assert_equal(3, local_location.start_line)
      assert_equal(3, local_location.end_line)
      assert_equal(5, local_location.start_column)
      assert_equal(6, local_location.end_column)
    end

    def test_multiple_lambda_vars_location
      tree = SyntaxTree.parse(<<~RUBY)
        # comment
        # comment
        ->(; a, b, c) { a }
      RUBY

      local_location =
        tree.statements.body.last.params.contents.locals.last.location

      assert_equal(3, local_location.start_line)
      assert_equal(3, local_location.end_line)
      assert_equal(11, local_location.start_column)
      assert_equal(12, local_location.end_column)
    end
  end
end
