# frozen_string_literal: true

require_relative "../test_helper"
require "parser/current"

Parser::Builders::Default.modernize

module SyntaxTree
  module Translation
    class ParserTest < Minitest::Test
      skips = %w[
        test_args_assocs_legacy:4041
        test_args_assocs:4091
        test_args_assocs:4091
        test_break_block:5204
        test_break:5169
        test_break:5183
        test_break:5189
        test_break:5196
        test_control_meta_escape_chars_in_regexp__since_31:*
        test_dedenting_heredoc:336
        test_dedenting_heredoc:392
        test_dedenting_heredoc:401
        test_forwarded_argument_with_kwrestarg:11332
        test_forwarded_argument_with_restarg:11267
        test_forwarded_kwrestarg_with_additional_kwarg:11306
        test_forwarded_kwrestarg:11287
        test_forwarded_restarg:11249
        test_hash_pair_value_omission:10364
        test_hash_pair_value_omission:10376
        test_if_while_after_class__since_32:11374
        test_if_while_after_class__since_32:11384
        test_kwoptarg_with_kwrestarg_and_forwarded_args:11482
        test_lvar_injecting_match:3819
        test_newline_in_hash_argument:11427
        test_next_block:5298
        test_next:5263
        test_next:5277
        test_next:5283
        test_next:5290
        test_next:5290
        test_parser_slash_slash_n_escaping_in_literals:*
        test_pattern_matching_explicit_array_match:8903
        test_pattern_matching_explicit_array_match:8928
        test_pattern_matching_expr_in_paren:9443
        test_pattern_matching_hash_with_string_keys:*
        test_pattern_matching_hash_with_string_keys:9264
        test_pattern_matching_hash:9186
        test_pattern_matching_implicit_array_match:8796
        test_pattern_matching_implicit_array_match:8841
        test_pattern_matching_numbered_parameter:9654
        test_pattern_matching_single_line_allowed_omission_of_parentheses:9868
        test_pattern_matching_single_line_allowed_omission_of_parentheses:9898
        test_redo:5310
        test_retry:5589
        test_send_index_asgn_kwarg_legacy:3642
        test_send_index_asgn_kwarg_legacy:3642
        test_send_index_asgn_kwarg:3629
        test_send_index_asgn_kwarg:3629
        test_slash_newline_in_heredocs:7379
        test_unary_num_pow_precedence:3519
        test_yield:3915
        test_yield:3923
        test_yield:3929
        test_yield:3937
      ]

      if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1.0")
        skips.push(
          "test_endless_method_forwarded_args_legacy:10139",
          "test_forward_arg_with_open_args:11114",
          "test_forward_arg:8090",
          "test_forward_args_legacy:8054",
          "test_forward_args_legacy:8066",
          "test_forward_args_legacy:8078",
          "test_pattern_matching_hash:*",
          "test_pattern_matching_single_line:9839",
          "test_trailing_forward_arg:8237"
        )
      end

      File
        .foreach(File.expand_path("parser.txt", __dir__), chomp: true)
        .slice_before { |line| line.start_with?("!!!") }
        .each do |(prefix, *lines)|
          name = prefix[4..]
          next if skips.any? { |skip| File.fnmatch?(skip, name) }

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
