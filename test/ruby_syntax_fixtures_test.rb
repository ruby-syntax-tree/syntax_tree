# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class RubySyntaxFixturesTest < Minitest::Test
    Dir[
      File.expand_path("ruby-syntax-fixtures/**/*.rb", __dir__)
    ].each do |file|
      define_method "test_ruby_syntax_fixtures_#{file}" do
        refute_nil(SyntaxTree.parse(SyntaxTree.read(file)))
      end
    end
  end
end
