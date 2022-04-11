# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class JSONVisitorTest < Minitest::Test
    Fixtures.each_fixture do |fixture|
      define_method(:"test_json_#{fixture.name}") do
        refute_includes(SyntaxTree.format(fixture.source).to_json, "#<")
      end
    end
  end
end
