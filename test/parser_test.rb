# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class ParserTest < Minitest::Test
    def test_parses_ripper_methods
      # First, get a list of all of the dispatched events from ripper.
      events = Ripper::EVENTS

      # Next, subtract all of the events that we have explicitly defined.
      events -= Parser.private_instance_methods(false).grep(/^on_(\w+)/) { $1.to_sym }

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
  end
end
