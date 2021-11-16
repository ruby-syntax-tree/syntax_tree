# frozen_string_literal: true

require 'simplecov'
SimpleCov.start

$LOAD_PATH.unshift(File.expand_path('../lib', __dir__))
require 'ripper/parse_tree'

require 'minitest/autorun'

class Minitest::Test
  private

  def assert_fixtures(filename)
    File
      .readlines(File.expand_path("fixtures/#{filename}", __dir__))
      .slice_before { |line| line == "%\n" }
      .each do |example|
        refute_nil(parse_tree(example))
      end
  end

  def assert_metadata(
    kind,
    node,
    start_char:,
    end_char:,
    start_line: 1,
    end_line: 1,
    **metadata
  )
    assert_kind_of(kind, node)

    assert_equal(start_line, node.location.start_line)
    assert_equal(start_char, node.location.start_char)
    assert_equal(end_line, node.location.end_line)
    assert_equal(end_char, node.location.end_char)

    metadata.each { |key, value| assert_equal(value, node.public_send(key)) }
  end

  def assert_node(kind, source)
    assert_metadata(
      kind,
      parse_tree(source),
      start_line: 1,
      start_char: 0,
      end_line: [1, source.count("\n")].max,
      end_char: source.chomp.size
    )
  end

  def parse_tree(source)
    parser = Ripper::ParseTree.new(source)
    response = parser.parse
    response.statements.body.first unless parser.error?
  end
end
