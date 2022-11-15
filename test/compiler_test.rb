# frozen_string_literal: true

return if !defined?(RubyVM::InstructionSequence) || RUBY_VERSION < "3.1"
require_relative "test_helper"

module SyntaxTree
  class CompilerTest < Minitest::Test
    CASES = [
      # Various literals placed on the stack
      "true",
      "false",
      "nil",
      "self",
      "0",
      "1",
      "2",
      "1.0",
      "1i",
      "1r",
      "1..2",
      "1...2",
      "(1)",
      "%w[foo bar baz]",
      "%W[foo bar baz]",
      "%i[foo bar baz]",
      "%I[foo bar baz]",
      "{ foo: 1, bar: 1.0, baz: 1i }",
      "'foo'",
      "\"foo\"",
      "\"foo\#{bar}\"",
      "\"foo\#@bar\"",
      "%q[foo]",
      "%Q[foo]",
      <<~RUBY,
        "foo" \\
          "bar"
      RUBY
      <<~RUBY,
        <<HERE
        content
        HERE
      RUBY
      <<~RUBY,
        <<-HERE
        content
        HERE
      RUBY
      <<~RUBY,
        <<~HERE
        content
        HERE
      RUBY
      <<~RUBY,
        <<-'HERE'
        content
        HERE
      RUBY
      <<~RUBY,
        <<-"HERE"
        content
        HERE
      RUBY
      <<~RUBY,
        <<-`HERE`
        content
        HERE
      RUBY
      ":foo",
      "/foo/",
      "/foo/i",
      "/foo/m",
      "/foo/x",
      # Various opt_* send specializations
      "1 + 2",
      "1 - 2",
      "1 * 2",
      "1 / 2",
      "1 % 2",
      "1 < 2",
      "1 <= 2",
      "1 > 2",
      "1 >= 2",
      "1 == 2",
      "1 != 2",
      "1 & 2",
      "1 | 2",
      "1 << 2",
      "1 ^ 2",
      "foo.empty?",
      "foo.length",
      "foo.nil?",
      "foo.size",
      "foo.succ",
      "/foo/ =~ \"foo\" && $1",
      # Various method calls
      "foo?",
      "foo.bar",
      "foo.bar(baz)",
      "foo bar",
      "foo.bar baz",
      "foo(*bar)",
      "foo(**bar)",
      "foo(&bar)",
      "foo.bar = baz",
      "not foo",
      "!foo",
      "~foo",
      "+foo",
      "-foo",
      "`foo`",
      "`foo \#{bar} baz`",
      # Local variables
      "foo",
      "foo = 1",
      "foo = 1; bar = 2; baz = 3",
      "foo = 1; foo",
      "foo += 1",
      "foo -= 1",
      "foo *= 1",
      "foo /= 1",
      "foo %= 1",
      "foo &= 1",
      "foo |= 1",
      "foo &&= 1",
      "foo ||= 1",
      "foo <<= 1",
      "foo ^= 1",
      # Instance variables
      "@foo",
      "@foo = 1",
      "@foo = 1; @bar = 2; @baz = 3",
      "@foo = 1; @foo",
      "@foo += 1",
      "@foo -= 1",
      "@foo *= 1",
      "@foo /= 1",
      "@foo %= 1",
      "@foo &= 1",
      "@foo |= 1",
      "@foo &&= 1",
      "@foo ||= 1",
      "@foo <<= 1",
      "@foo ^= 1",
      # Class variables
      "@@foo",
      "@@foo = 1",
      "@@foo = 1; @@bar = 2; @@baz = 3",
      "@@foo = 1; @@foo",
      "@@foo += 1",
      "@@foo -= 1",
      "@@foo *= 1",
      "@@foo /= 1",
      "@@foo %= 1",
      "@@foo &= 1",
      "@@foo |= 1",
      "@@foo &&= 1",
      "@@foo ||= 1",
      "@@foo <<= 1",
      "@@foo ^= 1",
      # Global variables
      "$foo",
      "$foo = 1",
      "$foo = 1; $bar = 2; $baz = 3",
      "$foo = 1; $foo",
      "$foo += 1",
      "$foo -= 1",
      "$foo *= 1",
      "$foo /= 1",
      "$foo %= 1",
      "$foo &= 1",
      "$foo |= 1",
      "$foo &&= 1",
      "$foo ||= 1",
      "$foo <<= 1",
      "$foo ^= 1",
      # Index access
      "foo[bar]",
      "foo[bar] = 1",
      "foo[bar] += 1",
      "foo[bar] -= 1",
      "foo[bar] *= 1",
      "foo[bar] /= 1",
      "foo[bar] %= 1",
      "foo[bar] &= 1",
      "foo[bar] |= 1",
      "foo[bar] &&= 1",
      "foo[bar] ||= 1",
      "foo[bar] <<= 1",
      "foo[bar] ^= 1",
      # Constants (single)
      "Foo",
      "Foo = 1",
      "Foo += 1",
      "Foo -= 1",
      "Foo *= 1",
      "Foo /= 1",
      "Foo %= 1",
      "Foo &= 1",
      "Foo |= 1",
      "Foo &&= 1",
      "Foo ||= 1",
      "Foo <<= 1",
      "Foo ^= 1",
      # Constants (top)
      "::Foo",
      "::Foo = 1",
      "::Foo += 1",
      "::Foo -= 1",
      "::Foo *= 1",
      "::Foo /= 1",
      "::Foo %= 1",
      "::Foo &= 1",
      "::Foo |= 1",
      "::Foo &&= 1",
      "::Foo ||= 1",
      "::Foo <<= 1",
      "::Foo ^= 1",
      # Constants (nested)
      "Foo::Bar::Baz",
      "Foo::Bar::Baz += 1",
      "Foo::Bar::Baz -= 1",
      "Foo::Bar::Baz *= 1",
      "Foo::Bar::Baz /= 1",
      "Foo::Bar::Baz %= 1",
      "Foo::Bar::Baz &= 1",
      "Foo::Bar::Baz |= 1",
      "Foo::Bar::Baz &&= 1",
      "Foo::Bar::Baz ||= 1",
      "Foo::Bar::Baz <<= 1",
      "Foo::Bar::Baz ^= 1",
      # Constants (top nested)
      "::Foo::Bar::Baz",
      "::Foo::Bar::Baz = 1",
      "::Foo::Bar::Baz += 1",
      "::Foo::Bar::Baz -= 1",
      "::Foo::Bar::Baz *= 1",
      "::Foo::Bar::Baz /= 1",
      "::Foo::Bar::Baz %= 1",
      "::Foo::Bar::Baz &= 1",
      "::Foo::Bar::Baz |= 1",
      "::Foo::Bar::Baz &&= 1",
      "::Foo::Bar::Baz ||= 1",
      "::Foo::Bar::Baz <<= 1",
      "::Foo::Bar::Baz ^= 1",
      # Constants (calls)
      "Foo::Bar.baz",
      "::Foo::Bar.baz",
      "Foo::Bar.baz = 1",
      "::Foo::Bar.baz = 1",
      # Control flow
      "foo && bar",
      "foo || bar",
      "if foo then bar end",
      "if foo then bar else baz end",
      "foo if bar",
      "foo while bar",
      "for i in [1, 2, 3] do i end",
      # Constructed values
      "foo..bar",
      "foo...bar",
      "[1, 1.0, 1i, 1r]",
      "[foo, bar, baz]",
      "[@foo, @bar, @baz]",
      "[@@foo, @@bar, @@baz]",
      "[$foo, $bar, $baz]",
      "%W[foo \#{bar} baz]",
      "%I[foo \#{bar} baz]",
      "[foo, bar] + [baz, qux]",
      "{ foo: bar, baz: qux }",
      "{ :foo => bar, :baz => qux }",
      "{ foo => bar, baz => qux }",
      "%s[foo]",
      "[$1, $2, $3, $4, $5, $6, $7, $8, $9]",
      "/foo \#{bar} baz/",
      "%r{foo \#{bar} baz}",
      # Core method calls
      "alias foo bar",
      "alias :foo :bar",
      "undef foo",
      "undef :foo",
      "undef foo, bar, baz",
      "undef :foo, :bar, :baz",
      "super",
      # defined? usage
      "defined?(foo)",
      "defined?(\"foo\")",
      "defined?(:foo)",
      "defined?(@foo)",
      "defined?(@@foo)",
      "defined?($foo)",
      "defined?(Foo)",
      "defined?(yield)",
      "defined?(super)",
      "foo = 1; defined?(foo)",
      "defined?(self)",
      "defined?(true)",
      "defined?(false)",
      "defined?(nil)",
      "defined?(foo = 1)",
      # Ignored content
      ";;;",
      "# comment",
      "=begin\nfoo\n=end",
      <<~RUBY,
        __END__
      RUBY
      # Method definitions
      "def foo; end",
      "def foo(bar); end",
      "def foo(bar, baz); end",
      "def foo(bar = 1); end",
      "def foo(bar = 1, baz = 2); end",
      "def foo(*bar); end",
      "def foo(bar, *baz); end",
      "def foo(*bar, baz, qux); end",
      "def foo(bar, *baz, qux); end",
      "def foo(bar, baz, *qux, quaz); end",
      # Class/module definitions
      "module Foo; end",
      "module ::Foo; end",
      "module Foo::Bar; end",
      "module ::Foo::Bar; end",
      "module Foo; module Bar; end; end"
    ]

    # These are the combinations of instructions that we're going to test.
    OPTIONS = [
      {},
      { frozen_string_literal: true },
      { operands_unification: false },
      { specialized_instruction: false },
      { operands_unification: false, specialized_instruction: false }
    ]

    OPTIONS.each do |options|
      suffix = options.inspect

      CASES.each do |source|
        define_method(:"test_#{source}_#{suffix}") do
          assert_compiles(source, **options)
        end
      end
    end

    private

    def serialize_iseq(iseq)
      serialized = iseq.to_a

      serialized[4].delete(:node_id)
      serialized[4].delete(:code_location)
      serialized[4].delete(:node_ids)

      serialized[13] = serialized[13].filter_map do |insn|
        next unless insn.is_a?(Array)

        insn.map do |operand|
          if operand.is_a?(Array) &&
               operand[0] == "YARVInstructionSequence/SimpleDataFormat"
            serialize_iseq(operand)
          else
            operand
          end
        end
      end

      serialized
    end

    def assert_compiles(source, **options)
      program = SyntaxTree.parse(source)

      assert_equal(
        serialize_iseq(RubyVM::InstructionSequence.compile(source, **options)),
        serialize_iseq(program.accept(Visitor::Compiler.new(**options)))
      )
    end
  end
end
