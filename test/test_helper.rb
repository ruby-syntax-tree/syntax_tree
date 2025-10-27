# frozen_string_literal: true

unless RUBY_ENGINE == "truffleruby"
  require "simplecov"
  SimpleCov.start do
    add_group("lib", "lib")
    add_group("test", "test")
  end
end

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "syntax_tree"

require "tempfile"
require "minitest/autorun"
