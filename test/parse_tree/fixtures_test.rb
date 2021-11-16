# frozen_string_literal: true

require 'test_helper'

class ParseTree
  class FixturesTest < Minitest::Test
    Dir[File.join('../fixtures/*.rb', __dir__)] do |filepath|
      define_method(:"test_#{File.basename(filepath, '.rb')}") do
        assert_fixtures(filepath)
      end
    end

    private

    def assert_fixtures(filepath)
      File
        .readlines(filepath)
        .slice_before { |line| line == "%\n" }
        .each do |source|
          parser = ParseTree.new(source.join[2..-1])

          refute_nil(parser.parse)
          refute(parser.error?)
        end
    end
  end
end
