# frozen_string_literal: true

return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.1"
require_relative "test_helper"

module SyntaxTree
  class YARVTest < Minitest::Test
    CASES = {
      "0" => "return 0\n",
      "1" => "return 1\n",
      "2" => "return 2\n",
      "1.0" => "return 1.0\n",
      "1 + 2" => "return 1 + 2\n",
      "1 - 2" => "return 1 - 2\n",
      "1 * 2" => "return 1 * 2\n",
      "1 / 2" => "return 1 / 2\n",
      "1 % 2" => "return 1 % 2\n",
      "1 < 2" => "return 1 < 2\n",
      "1 <= 2" => "return 1 <= 2\n",
      "1 > 2" => "return 1 > 2\n",
      "1 >= 2" => "return 1 >= 2\n",
      "1 == 2" => "return 1 == 2\n",
      "1 != 2" => "return 1 != 2\n",
      "1 & 2" => "return 1 & 2\n",
      "1 | 2" => "return 1 | 2\n",
      "1 << 2" => "return 1 << 2\n",
      "1 >> 2" => "return 1.>>(2)\n",
      "1 ** 2" => "return 1.**(2)\n",
      "a = 1; a" => "a = 1\nreturn a\n",
    }.freeze

    CASES.each do |source, expected|
      define_method("test_disassemble_#{source}") do
        assert_disassembles(expected, source)
      end
    end

    private

    def assert_disassembles(expected, source)
      iseq = SyntaxTree.parse(source).accept(Compiler.new)
      actual = Formatter.format(source, YARV::Disassembler.new(iseq).to_ruby)
      assert_equal expected, actual
    end
  end
end
