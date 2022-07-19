# frozen_string_literal: true

require_relative "test_helper"

module SyntaxTree
  class CLITest < Minitest::Test
    class TestHandler
      def parse(source)
        source * 2
      end

      def read(filepath)
        File.read(filepath)
      end
    end

    def test_handler
      SyntaxTree.register_handler(".test", TestHandler.new)

      file = Tempfile.new(%w[test- .test])
      file.puts("test")

      result = run_cli("ast", file: file)
      assert_equal("\"test\\n\" + \"test\\n\"\n", result.stdio)
    ensure
      SyntaxTree::HANDLERS.delete(".test")
    end

    def test_ast
      result = run_cli("ast")
      assert_includes(result.stdio, "ident \"test\"")
    end

    def test_ast_syntax_error
      file = Tempfile.new(%w[test- .rb])
      file.puts("foo\n<>\nbar\n")

      result = run_cli("ast", file: file)
      assert_includes(result.stderr, "syntax error")
    end

    def test_check
      result = run_cli("check")
      assert_includes(result.stdio, "match")
    end

    def test_check_unformatted
      file = Tempfile.new(%w[test- .rb])
      file.write("foo")

      result = run_cli("check", file: file)
      assert_includes(result.stderr, "expected")
    end

    def test_check_print_width
      file = Tempfile.new(%w[test- .rb])
      file.write("#{"a" * 40} + #{"b" * 40}\n")

      result = run_cli("check", "--print-width=100", file: file)
      assert_includes(result.stdio, "match")
    end

    def test_debug
      result = run_cli("debug")
      assert_includes(result.stdio, "idempotently")
    end

    def test_debug_non_idempotent_format
      formats = 0
      formatting = ->(*) { (formats += 1).to_s }

      SyntaxTree.stub(:format, formatting) do
        result = run_cli("debug")
        assert_includes(result.stderr, "idempotently")
      end
    end

    def test_doc
      result = run_cli("doc")
      assert_includes(result.stdio, "test")
    end

    def test_format
      result = run_cli("format")
      assert_equal("test\n", result.stdio)
    end

    def test_json
      result = run_cli("json")
      assert_includes(result.stdio, "\"type\": \"program\"")
    end

    def test_match
      result = run_cli("match")
      assert_includes(result.stdio, "SyntaxTree::Program")
    end

    def test_version
      result = run_cli("version")
      assert_includes(result.stdio, SyntaxTree::VERSION.to_s)
    end

    def test_write
      file = Tempfile.new(%w[test- .test])
      filepath = file.path

      result = run_cli("write", file: file)
      assert_includes(result.stdio, filepath)
    end

    def test_write_syntax_tree
      file = Tempfile.new(%w[test- .rb])
      file.write("<>")

      result = run_cli("write", file: file)
      assert_includes(result.stderr, "syntax error")
    end

    def test_help
      stdio, = capture_io { SyntaxTree::CLI.run(["help"]) }
      assert_includes(stdio, "stree help")
    end

    def test_help_default
      *, stderr = capture_io { SyntaxTree::CLI.run(["foobar"]) }
      assert_includes(stderr, "stree help")
    end

    def test_no_arguments
      $stdin.stub(:tty?, true) do
        *, stderr = capture_io { SyntaxTree::CLI.run(["check"]) }
        assert_includes(stderr, "stree help")
      end
    end

    def test_no_arguments_no_tty
      stdin = $stdin
      $stdin = StringIO.new("1+1")

      stdio, = capture_io { SyntaxTree::CLI.run(["format"]) }
      assert_equal("1 + 1\n", stdio)
    ensure
      $stdin = stdin
    end

    def test_generic_error
      SyntaxTree.stub(:format, ->(*) { raise }) do
        result = run_cli("format")
        refute_equal(0, result.status)
      end
    end

    def test_plugins
      Dir.mktmpdir do |directory|
        Dir.mkdir(File.join(directory, "syntax_tree"))
        $:.unshift(directory)

        File.write(
          File.join(directory, "syntax_tree", "plugin.rb"),
          "puts 'Hello, world!'"
        )
        result = run_cli("format", "--plugins=plugin")

        assert_equal("Hello, world!\ntest\n", result.stdio)
      end
    end

    def test_language_server
      prev_stdin = $stdin
      prev_stdout = $stdout

      request = { method: "shutdown" }.merge(jsonrpc: "2.0").to_json
      $stdin =
        StringIO.new("Content-Length: #{request.bytesize}\r\n\r\n#{request}")
      $stdout = StringIO.new

      assert_equal(0, SyntaxTree::CLI.run(["lsp"]))
    ensure
      $stdin = prev_stdin
      $stdout = prev_stdout
    end

    private

    Result = Struct.new(:status, :stdio, :stderr, keyword_init: true)

    def run_cli(command, *args, file: nil)
      if file.nil?
        file = Tempfile.new(%w[test- .rb])
        file.puts("test")
      end

      file.rewind

      status = nil
      stdio, stderr =
        capture_io { status = SyntaxTree::CLI.run([command, *args, file.path]) }

      Result.new(status: status, stdio: stdio, stderr: stderr)
    ensure
      file.close
      file.unlink
    end
  end
end
