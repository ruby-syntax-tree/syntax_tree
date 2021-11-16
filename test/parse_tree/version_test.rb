# frozen_string_literal: true

require 'test_helper'

class ParseTree
  class VersionTest < Minitest::Test
    def test_version
      refute_nil(VERSION)
    end
  end
end
