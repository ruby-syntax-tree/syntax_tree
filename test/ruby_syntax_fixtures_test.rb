# frozen_string_literal: true

# The ruby-syntax-fixtures repository tests against the current Ruby syntax, so
# we don't execute this test unless we're running 3.2 or above.
return unless RUBY_VERSION >= "3.2"

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
