# frozen_string_literal: true

require 'test_helper'

class ParseTreeTest < Minitest::Test
  def test_version
    refute_nil Ripper::ParseTree::VERSION
  end
end
