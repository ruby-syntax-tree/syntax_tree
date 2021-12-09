# frozen_string_literal: true

require "simplecov"
SimpleCov.start { add_filter("prettyprint.rb") }

$LOAD_PATH.unshift(File.expand_path("../lib", __dir__))
require "syntax_tree"

require "json"
require "pp"
require "minitest/autorun"
