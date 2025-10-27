# frozen_string_literal: true

return if !defined?(Ractor) || Gem.win_platform?

# Before Ruby 3.4.0, autoloads could not happen on a non-default Ractor.
require "prism/parse_result/comments" if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.4.0")

require_relative "test_helper"

module SyntaxTree
  class RactorTest < Minitest::Test
    def test_ractors
      ractors =
        Dir[File.join(__dir__, "*.rb")].map do |filepath|
          without_experimental_warnings do
            Ractor.new(filepath) { |filepath| SyntaxTree.format_file(filepath) }
          end
        end

      ractors.each do |ractor|
        # Somewhere in the Ruby 3.5.* series, Ractor#take was removed and
        # Ractor#value was added.
        value = ractor.respond_to?(:value) ? ractor.value : ractor.take
        assert_kind_of(String, value)
      end
    end

    private

    def without_experimental_warnings
      previous = Warning[:experimental]

      begin
        Warning[:experimental] = false
        yield
      ensure
        Warning[:experimental] = previous
      end
    end
  end
end
