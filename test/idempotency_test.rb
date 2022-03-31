# frozen_string_literal: true

return if ENV["FAST"]
require_relative "test_helper"

module SyntaxTree
  class IdempotencyTest < Minitest::Test
    Dir[File.join(RbConfig::CONFIG["libdir"], "**/*.rb")].each do |filepath|
      define_method(:"test_#{filepath}") do
        source = SyntaxTree.read(filepath)
        formatted = SyntaxTree.format(source)

        assert_equal(formatted, SyntaxTree.format(formatted), "expected #{filepath} to be formatted idempotently")
      end
    end
  end
end
