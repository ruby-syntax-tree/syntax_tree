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
      assert_equal(2, error.column)
    end

    def test_errors_on_missing_end_with_location
      error = assert_raises(Parser::ParseError) { SyntaxTree.parse("foo do 1") }
      assert_equal(4, error.column)
    end

    def test_errors_on_missing_regexp_ending
      error =
        assert_raises(Parser::ParseError) { SyntaxTree.parse("a =~ /foo") }

      assert_equal(5, error.column)
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
  end
end
