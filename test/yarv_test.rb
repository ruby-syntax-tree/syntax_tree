# frozen_string_literal: true

return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.1"
require_relative "test_helper"

module SyntaxTree
  class YARVTest < Minitest::Test
    CASES = {
      "0" => "break 0\n",
      "1" => "break 1\n",
      "2" => "break 2\n",
      "1.0" => "break 1.0\n",
      "1 + 2" => "break 1 + 2\n",
      "1 - 2" => "break 1 - 2\n",
      "1 * 2" => "break 1 * 2\n",
      "1 / 2" => "break 1 / 2\n",
      "1 % 2" => "break 1 % 2\n",
      "1 < 2" => "break 1 < 2\n",
      "1 <= 2" => "break 1 <= 2\n",
      "1 > 2" => "break 1 > 2\n",
      "1 >= 2" => "break 1 >= 2\n",
      "1 == 2" => "break 1 == 2\n",
      "1 != 2" => "break 1 != 2\n",
      "1 & 2" => "break 1 & 2\n",
      "1 | 2" => "break 1 | 2\n",
      "1 << 2" => "break 1 << 2\n",
      "1 >> 2" => "break 1.>>(2)\n",
      "1 ** 2" => "break 1.**(2)\n",
      "a = 1; a" => "a = 1\nbreak a\n"
    }.freeze

    CASES.each do |source, expected|
      define_method("test_disassemble_#{source}") do
        assert_decompiles(expected, source)
      end
    end

    def test_bf
      hello_world =
        "++++++++[>++++[>++>+++>+++>+<<<<-]>+>+>->>+[<]<-]" \
          ">>.>---.+++++++..+++.>>.<-.<.+++.------.--------.>>+.>++."

      iseq = YARV::Bf.new(hello_world).compile
      Formatter.format(hello_world, YARV::Decompiler.new(iseq).to_ruby)
    end

    private

    def assert_decompiles(expected, source)
      ruby = YARV::Decompiler.new(YARV.compile(source)).to_ruby
      actual = Formatter.format(source, ruby)
      assert_equal expected, actual
    end
  end
end
