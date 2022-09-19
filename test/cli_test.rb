# frozen_string_literal: true

require_relative "test_helper"
require "securerandom"

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

      result = run_cli("ast", contents: file)
      assert_equal("\"test\\n\" + \"test\\n\"\n", result.stdio)
    ensure
      SyntaxTree::HANDLERS.delete(".test")
    end

    def test_ast
      result = run_cli("ast")
      assert_includes(result.stdio, "ident \"test\"")
    end

    def test_ast_ignore
      result = run_cli("ast", "--ignore-files='*/test*'")
      assert_equal(0, result.status)
      assert_empty(result.stdio)
    end

    def test_ast_syntax_error
      result = run_cli("ast", contents: "foo\n<>\nbar\n")
      assert_includes(result.stderr, "syntax error")
    end

    def test_check
      result = run_cli("check")
      assert_includes(result.stdio, "match")
    end

    def test_check_unformatted
      result = run_cli("check", contents: "foo")
      assert_includes(result.stderr, "expected")
    end

    def test_check_print_width
      contents = "#{"a" * 40} + #{"b" * 40}\n"
      result = run_cli("check", "--print-width=100", contents: contents)
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

      result = run_cli("write", contents: file)
      assert_includes(result.stdio, filepath)
    end

    def test_write_syntax_tree
      result = run_cli("write", contents: "<>")
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
      with_tty do
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

    def test_inline_script
      with_tty do
        stdio, = capture_io { SyntaxTree::CLI.run(%w[format -e 1+1]) }
        assert_equal("1 + 1\n", stdio)
      end
    end

    def test_multiple_inline_scripts
      with_tty do
        stdio, = capture_io { SyntaxTree::CLI.run(%w[format -e 1+1 -e 2+2]) }
        assert_equal("1 + 1\n2 + 2\n", stdio)
      end
    end

    def test_generic_error
      SyntaxTree.stub(:format, ->(*) { raise }) do
        result = run_cli("format")

        refute_equal(0, result.status)
      end
    end

    def test_plugins
      with_plugin_directory do |directory|
        plugin = directory.plugin("puts 'Hello, world!'")
        result = run_cli("format", "--plugins=#{plugin}")

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

    def test_config_file
      with_plugin_directory do |directory|
        plugin = directory.plugin("puts 'Hello, world!'")
        config = <<~TXT
        --print-width=100
        --plugins=#{plugin}
        TXT

        with_config_file(config) do
          contents = "#{"a" * 40} + #{"b" * 40}\n"
          result = run_cli("format", contents: contents)

          assert_equal("Hello, world!\n#{contents}", result.stdio)
        end
      end
    end

    def test_print_width_args_with_config_file
      with_config_file("--print-width=100") do
        result = run_cli("check", contents: "#{"a" * 40} + #{"b" * 40}\n")

        assert_includes(result.stdio, "match")
      end
    end

    def test_print_width_args_with_config_file_override
      with_config_file("--print-width=100") do
        contents = "#{"a" * 40} + #{"b" * 40}\n"
        result = run_cli("check", "--print-width=82", contents: contents)

        assert_includes(result.stderr, "expected")
      end
    end

    def test_plugin_args_with_config_file
      with_plugin_directory do |directory|
        plugin1 = directory.plugin("puts 'Hello, world!'")

        with_config_file("--plugins=#{plugin1}") do
          plugin2 = directory.plugin("puts 'Bye, world!'")
          result = run_cli("format", "--plugins=#{plugin2}")

          assert_equal("Hello, world!\nBye, world!\ntest\n", result.stdio)
        end
      end
    end

    private

    Result = Struct.new(:status, :stdio, :stderr, keyword_init: true)

    def run_cli(command, *args, contents: :default)
      tempfile =
        case contents
        when :default
          Tempfile.new(%w[test- .rb]).tap { |file| file.puts("test") }
        when String
          Tempfile.new(%w[test- .rb]).tap { |file| file.write(contents) }
        else
          contents
        end

      tempfile.rewind

      status = nil
      stdio, stderr =
        with_tty do
          capture_io do
            status = SyntaxTree::CLI.run([command, *args, tempfile.path])
          end
        end

      Result.new(status: status, stdio: stdio, stderr: stderr)
    ensure
      tempfile.close
      tempfile.unlink
    end

    def with_tty(&block)
      $stdin.stub(:tty?, true, &block)
    end

    def with_config_file(contents)
      filepath = File.join(Dir.pwd, SyntaxTree::CLI::ConfigFile::FILENAME)
      File.write(filepath, contents)

      yield
    ensure
      FileUtils.rm(filepath)
    end

    class PluginDirectory
      attr_reader :directory

      def initialize(directory)
        @directory = directory
      end

      def plugin(contents)
        name = SecureRandom.hex
        File.write(File.join(directory, "#{name}.rb"), contents)
        name
      end
    end

    def with_plugin_directory
      Dir.mktmpdir do |directory|
        $:.unshift(directory)

        plugin_directory = File.join(directory, "syntax_tree")
        Dir.mkdir(plugin_directory)

        yield PluginDirectory.new(plugin_directory)
      end
    end
  end
end
