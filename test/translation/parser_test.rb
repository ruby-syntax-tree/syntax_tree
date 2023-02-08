# frozen_string_literal: true

require_relative "../test_helper"
require "parser/current"

Parser::Builders::Default.modernize

module SyntaxTree
  module Translation
    class ParserTest < Minitest::Test
      known_failures = [
        # I think this may be a bug in the parser gem's precedence calculation.
        # Unary plus appears to be parsed as part of the number literal in
        # CRuby, but parser is parsing it as a separate operator.
        "test_unary_num_pow_precedence:3505",

        # Not much to be done about this. Basically, regular expressions with
        # named capture groups that use the =~ operator inject local variables
        # into the current scope. In the parser gem, it detects this and changes
        # future references to that name to be a local variable instead of a
        # potential method call. CRuby does not do this.
        "test_lvar_injecting_match:3778",

        # This is failing because CRuby is not marking values captured in hash
        # patterns as local variables, while the parser gem is.
        "test_pattern_matching_hash:8971",

        # This is not actually allowed in the CRuby parser but the parser gem
        # thinks it is allowed.
        "test_pattern_matching_hash_with_string_keys:9016",
        "test_pattern_matching_hash_with_string_keys:9027",
        "test_pattern_matching_hash_with_string_keys:9038",
        "test_pattern_matching_hash_with_string_keys:9060",
        "test_pattern_matching_hash_with_string_keys:9071",
        "test_pattern_matching_hash_with_string_keys:9082",

        # This happens with pattern matching where you're matching a literal
        # value inside parentheses, which doesn't really do anything. Ripper
        # doesn't capture that this value is inside a parentheses, so it's hard
        # to translate properly.
        "test_pattern_matching_expr_in_paren:9206",

        # These are also failing because of CRuby not marking values captured in
        # hash patterns as local variables.
        "test_pattern_matching_single_line_allowed_omission_of_parentheses:*",

        # I'm not even sure what this is testing, because the code is invalid in
        # CRuby.
        "test_control_meta_escape_chars_in_regexp__since_31:*",
      ]

      todo_failures = [
        "test_dedenting_heredoc:334",
        "test_dedenting_heredoc:390",
        "test_dedenting_heredoc:399",
        "test_slash_newline_in_heredocs:7194",
        "test_parser_slash_slash_n_escaping_in_literals:*",
        "test_cond_match_current_line:4801",
        "test_forwarded_restarg:*",
        "test_forwarded_kwrestarg:*",
        "test_forwarded_argument_with_restarg:*",
        "test_forwarded_argument_with_kwrestarg:*"
      ]

      current_version = RUBY_VERSION.split(".")[0..1].join(".")

      if current_version <= "2.7"
        # I'm not sure why this is failing on 2.7.0, but we'll turn it off for
        # now until we have more time to investigate.
        todo_failures.push(
          "test_pattern_matching_hash:*",
          "test_pattern_matching_single_line:9552"
        )
      end
    
      if current_version <= "3.0"
        # In < 3.0, there are some changes to the way the parser gem handles
        # forwarded args. We should eventually support this, but for now we're
        # going to mark them as todo.
        todo_failures.push(
          "test_forward_arg:*",
          "test_forward_args_legacy:*",
          "test_endless_method_forwarded_args_legacy:*",
          "test_trailing_forward_arg:*",
          "test_forward_arg_with_open_args:10770",
        )
      end
    
      if current_version == "3.1"
        # This test actually fails on 3.1.0, even though it's marked as being
        # since 3.1. So we're going to skip this test on 3.1, but leave it in
        # for other versions.
        known_failures.push(
          "test_multiple_pattern_matches:11086",
          "test_multiple_pattern_matches:11102"
        )
      end

      if current_version < "3.2" || RUBY_ENGINE == "truffleruby"
        known_failures.push(
          "test_if_while_after_class__since_32:11004",
          "test_if_while_after_class__since_32:11014",
          "test_newline_in_hash_argument:11057"
        )
      end

      all_failures = known_failures + todo_failures

      File
        .foreach(File.expand_path("parser.txt", __dir__), chomp: true)
        .slice_before { |line| line.start_with?("!!!") }
        .each do |(prefix, *lines)|
          name = prefix[4..]
          next if all_failures.any? { |pattern| File.fnmatch?(pattern, name) }

          define_method(name) { assert_parses("#{lines.join("\n")}\n") }
        end

      private

      def assert_parses(source)
        parser = ::Parser::CurrentRuby.default_parser
        parser.diagnostics.consumer = ->(*) {}

        buffer = ::Parser::Source::Buffer.new("(string)", 1)
        buffer.source = source

        expected =
          begin
            parser.parse(buffer)
          rescue ::Parser::SyntaxError
            # We can get a syntax error if we're parsing a fixture that was
            # designed for a later Ruby version but we're running an earlier
            # Ruby version. In this case we can just return early from the test.
          end

        return if expected.nil?
        node = SyntaxTree.parse(source)
        assert_equal expected, SyntaxTree::Translation.to_parser(node, buffer)
      end
    end
  end
end

if ENV["PARSER_LOCATION"]
  # Modify the source map == check so that it doesn't check against the node
  # itself so we don't get into a recursive loop.
  Parser::Source::Map.prepend(
    Module.new do
      def ==(other)
        self.class == other.class &&
          (instance_variables - %i[@node]).map do |ivar|
            instance_variable_get(ivar) == other.instance_variable_get(ivar)
          end.reduce(:&)
      end
    end
  )

  # Next, ensure that we're comparing the nodes and also comparing the source
  # ranges so that we're getting all of the necessary information.
  Parser::AST::Node.prepend(
    Module.new do
      def ==(other)
        super && (location == other.location)
      end
    end
  )
end
