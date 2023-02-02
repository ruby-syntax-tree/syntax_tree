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
      "a = 1; a" => "a = 1\nreturn a\n"
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
      stdout, = capture_io { iseq.eval }
      assert_equal "Hello World!\n", stdout

      Formatter.format(hello_world, YARV::Decompiler.new(iseq).to_ruby)
    end

    # rubocop:disable Layout/LineLength
    EMULATION_CASES = {
      # adjuststack
      "x = [true]; x[0] ||= nil; x[0]" => true,
      # anytostring
      "\"\#{5}\"" => "5",
      "class A2Str; def to_s; 1; end; end; \"\#{A2Str.new}\"" =>
        "#<A2Str:0000>",
      # branchif
      "x = true; x ||= \"foo\"; x" => true,
      # branchnil
      "x = nil; if x&.to_s; 'hi'; else; 'bye'; end" => "bye",
      # branchunless
      "if 2 + 3; 'hi'; else; 'bye'; end" => "hi",
      # checkkeyword
      # "def evaluate(value: rand); value.floor; end; evaluate" => 0,
      # checkmatch
      "'foo' in String" => true,
      "case 1; when *[1, 2, 3]; true; end" => true,
      # checktype
      "['foo'] in [String]" => true,
      # concatarray
      "[1, *2]" => [1, 2],
      # concatstrings
      "\"\#{7}\"" => "7",
      # defineclass
      "class DefineClass; def bar; end; end" => :bar,
      "module DefineModule; def bar; end; end" => :bar,
      "class << self; self; end" =>
        TOPLEVEL_BINDING.eval("self").singleton_class,
      # defined
      "defined?(1)" => "expression",
      "defined?(foo = 1)" => "assignment",
      "defined?(Object)" => "constant",
      # definemethod
      "def definemethod = 5; definemethod" => 5,
      # definesmethod
      "def self.definesmethod = 5; self.definesmethod" => 5,
      # dup
      "$global = 5" => 5,
      # duparray
      "[true]" => [true],
      # duphash
      "{ a: 1 }" => {
        a: 1
      },
      # dupn
      "Object::X ||= true" => true,
      # expandarray
      "x, = [true, false, nil]" => [true, false, nil],
      "*, x = [true, false, nil]" => [true, false, nil],
      # getblockparam
      "def getblockparam(&block); block; end; getblockparam { 1 }.call" => 1,
      # getblockparamproxy
      "def getblockparamproxy(&block); block.call; end; getblockparamproxy { 1 }" =>
        1,
      # getclassvariable
      "class CVar; @@foo = 5; end; class << CVar; @@foo; end" => 5,
      # getconstant
      "Object" => Object,
      # getglobal
      "$$" => $$,
      # getinstancevariable
      "@foo = 5; @foo" => 5,
      # getlocal
      "value = 5; self.then { self.then { self.then { value } } }" => 5,
      # getlocalwc0
      "value = 5; value" => 5,
      # getlocalwc1
      "value = 5; self.then { value }" => 5,
      # getspecial
      "1 if (2 == 2) .. (3 == 3)" => 1,
      # intern
      ":\"foo\#{1}\"" => :foo1,
      # invokeblock
      "def invokeblock = yield; invokeblock { 1 }" => 1,
      # invokesuper
      <<~RUBY => 2,
        class Parent
          def value
            1
          end
        end

        class Child < Parent
          def value
            super + 1
          end
        end

        Child.new.value
      RUBY
      # jump
      "x = 0; if x == 0 then 1 else 2 end" => 1,
      # newarray
      "[\"value\"]" => ["value"],
      # newarraykwsplat
      "[\"string\", **{ foo: \"bar\" }]" => ["string", { foo: "bar" }],
      # newhash
      "def newhash(key, value) = { key => value }; newhash(1, 2)" => {
        1 => 2
      },
      # newrange
      "x = 0; y = 1; (x..y).to_a" => [0, 1],
      # nop
      # objtostring
      "\"\#{6}\"" => "6",
      # once
      "/\#{1}/o" => /1/o,
      # opt_and
      "0b0110 & 0b1011" => 0b0010,
      # opt_aref
      "x = [1, 2, 3]; x[1]" => 2,
      # opt_aref_with
      "x = { \"a\" => 1 }; x[\"a\"]" => 1,
      # opt_aset
      "x = [1, 2, 3]; x[1] = 4; x" => [1, 4, 3],
      # opt_aset_with
      "x = { \"a\" => 1 }; x[\"a\"] = 2; x" => {
        "a" => 2
      },
      # opt_case_dispatch
      <<~RUBY => "foo",
        case 1
        when 1
          "foo"
        else
          "bar"
        end
      RUBY
      # opt_div
      "5 / 2" => 2,
      # opt_empty_p
      "[].empty?" => true,
      # opt_eq
      "1 == 1" => true,
      # opt_ge
      "1 >= 1" => true,
      # opt_getconstant_path
      "::Object" => Object,
      # opt_gt
      "1 > 1" => false,
      # opt_le
      "1 <= 1" => true,
      # opt_length
      "[1, 2, 3].length" => 3,
      # opt_lt
      "1 < 1" => false,
      # opt_ltlt
      "\"\" << 2" => "\u0002",
      # opt_minus
      "1 - 1" => 0,
      # opt_mod
      "5 % 2" => 1,
      # opt_mult
      "5 * 2" => 10,
      # opt_neq
      "1 != 1" => false,
      # opt_newarray_max
      "def opt_newarray_max(a, b, c) = [a, b, c].max; opt_newarray_max(1, 2, 3)" =>
        3,
      # opt_newarray_min
      "def opt_newarray_min(a, b, c) = [a, b, c].min; opt_newarray_min(1, 2, 3)" =>
        1,
      # opt_nil_p
      "nil.nil?" => true,
      # opt_not
      "!true" => false,
      # opt_or
      "0b0110 | 0b1011" => 0b1111,
      # opt_plus
      "1 + 1" => 2,
      # opt_regexpmatch2
      "/foo/ =~ \"~~~foo\"" => 3,
      # opt_send_without_block
      "5.to_s" => "5",
      # opt_size
      "[1, 2, 3].size" => 3,
      # opt_str_freeze
      "\"foo\".freeze" => "foo",
      # opt_str_uminus
      "-\"foo\"" => -"foo",
      # opt_succ
      "1.succ" => 2,
      # pop
      "a ||= 2; a" => 2,
      # putnil
      "[nil]" => [nil],
      # putobject
      "2" => 2,
      # putobject_INT2FIX_0_
      "0" => 0,
      # putobject_INT2FIX_1_
      "1" => 1,
      # putself
      "self" => TOPLEVEL_BINDING.eval("self"),
      # putspecialobject
      "[class Undef; def foo = 1; undef foo; end]" => [nil],
      # putstring
      "\"foo\"" => "foo",
      # send
      "\"hello\".then { |value| value }" => "hello",
      # setblockparam
      "def setblockparam(&bar); bar = -> { 1 }; bar.call; end; setblockparam" =>
        1,
      # setclassvariable
      "class CVarSet; @@foo = 1; end; class << CVarSet; @@foo = 10; end" => 10,
      # setconstant
      "SetConstant = 1" => 1,
      # setglobal
      "$global = 10" => 10,
      # setinstancevariable
      "@ivar = 5" => 5,
      # setlocal
      "x = 5; tap { tap { tap { x = 10 } } }; x" => 10,
      # setlocal_WC_0
      "x = 5; x" => 5,
      # setlocal_WC_1
      "x = 5; tap { x = 10 }; x" => 10,
      # setn
      "{}[:key] = 'value'" => "value",
      # setspecial
      "1 if (1 == 1) .. (2 == 2)" => 1,
      # splatarray
      "x = *(5)" => [5],
      # swap
      "!!defined?([[]])" => true,
      # throw
      # topn
      "case 3; when 1..5; 'foo'; end" => "foo",
      # toregexp
      "/abc \#{1 + 2} def/" => /abc 3 def/
    }.freeze
    # rubocop:enable Layout/LineLength

    EMULATION_CASES.each do |source, expected|
      define_method("test_emulate_#{source}") do
        assert_emulates(expected, source)
      end
    end

    ObjectSpace.each_object(YARV::Instruction.singleton_class) do |instruction|
      next if instruction == YARV::Instruction

      define_method("test_instruction_interface_#{instruction.name}") do
        methods = instruction.instance_methods(false)
        assert_empty(%i[disasm to_a deconstruct_keys call ==] - methods)
      end
    end

    private

    def assert_decompiles(expected, source)
      ruby = YARV::Decompiler.new(YARV.compile(source)).to_ruby
      actual = Formatter.format(source, ruby)
      assert_equal expected, actual
    end

    def assert_emulates(expected, source)
      ruby_iseq = RubyVM::InstructionSequence.compile(source)
      yarv_iseq = YARV::InstructionSequence.from(ruby_iseq.to_a)

      exercise_iseq(yarv_iseq)
      result = SyntaxTree::YARV::VM.new.run_top_frame(yarv_iseq)
      assert_equal(expected, result)
    end

    def exercise_iseq(iseq)
      iseq.disasm
      iseq.to_a

      iseq.insns.each do |insn|
        case insn
        when YARV::InstructionSequence::Label, Integer, Symbol
          next
        end

        insn.pushes
        insn.pops
        insn.canonical

        case insn
        when YARV::DefineClass
          exercise_iseq(insn.class_iseq)
        when YARV::DefineMethod, YARV::DefineSMethod
          exercise_iseq(insn.method_iseq)
        when YARV::InvokeSuper, YARV::Send
          exercise_iseq(insn.block_iseq) if insn.block_iseq
        when YARV::Once
          exercise_iseq(insn.iseq)
        end
      end
    end
  end
end
