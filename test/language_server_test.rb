# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/language_server"

module SyntaxTree
  # stree-ignore
  class LanguageServerTest < Minitest::Test
    class Initialize
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def to_hash
        { method: "initialize", id: id }
      end
    end

    class Shutdown
      attr_reader :id

      def initialize(id)
        @id = id
      end

      def to_hash
        { method: "shutdown", id: id }
      end
    end

    class TextDocumentDidOpen
      attr_reader :uri, :text

      def initialize(uri, text)
        @uri = uri
        @text = text
      end

      def to_hash
        {
          method: "textDocument/didOpen",
          params: { textDocument: { uri: uri, text: text } }
        }
      end
    end

    class TextDocumentDidChange
      attr_reader :uri, :text

      def initialize(uri, text)
        @uri = uri
        @text = text
      end

      def to_hash
        {
          method: "textDocument/didChange",
          params: {
            textDocument: { uri: uri },
            contentChanges: [{ text: text }]
          }
        }
      end
    end

    class TextDocumentDidClose
      attr_reader :uri

      def initialize(uri)
        @uri = uri
      end

      def to_hash
        {
          method: "textDocument/didClose",
          params: { textDocument: { uri: uri } }
        }
      end
    end

    class TextDocumentFormatting
      attr_reader :id, :uri

      def initialize(id, uri)
        @id = id
        @uri = uri
      end

      def to_hash
        {
          method: "textDocument/formatting",
          id: id,
          params: { textDocument: { uri: uri } }
        }
      end
    end

    class TextDocumentInlayHint
      attr_reader :id, :uri

      def initialize(id, uri)
        @id = id
        @uri = uri
      end

      def to_hash
        {
          method: "textDocument/inlayHint",
          id: id,
          params: { textDocument: { uri: uri } }
        }
      end
    end

    class SyntaxTreeVisualizing
      attr_reader :id, :uri

      def initialize(id, uri)
        @id = id
        @uri = uri
      end

      def to_hash
        {
          method: "syntaxTree/visualizing",
          id: id,
          params: { textDocument: { uri: uri } }
        }
      end
    end

    def test_formatting
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "class Foo; end"),
        TextDocumentDidChange.new("file:///path/to/file.rb", "class Bar; end"),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        TextDocumentDidClose.new("file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: [{ newText: :any }] },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal("class Bar\nend\n", responses.dig(1, :result, 0, :newText))
    end

    def test_formatting_ignore
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "class Foo; end"),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ], ignore_files: ["path/**/*.rb"])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_nil(responses.dig(1, :result))
    end

    def test_formatting_failure
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "<>"),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_nil(responses.dig(1, :result))
    end

    def test_formatting_print_width
      contents = "#{"a" * 40} + #{"b" * 40}\n"
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", contents),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        TextDocumentDidClose.new("file:///path/to/file.rb"),
        Shutdown.new(3)
      ], print_width: 100)

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: [{ newText: :any }] },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal(contents, responses.dig(1, :result, 0, :newText))
    end

    def test_inlay_hint
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          begin
            1 + 2 * 3
          rescue
          end
        RUBY
        TextDocumentInlayHint.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal(3, responses.dig(1, :result).size)
    end

    def test_inlay_hint_invalid
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "<>"),
        TextDocumentInlayHint.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal(0, responses.dig(1, :result).size)
    end

    def test_visualizing
      responses = run_server([
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "1 + 2"),
        SyntaxTreeVisualizing.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
      assert_equal(
        "(program (statements ((binary (int \"1\") + (int \"2\")))))\n",
        responses.dig(1, :result)
      )
    end

    def test_reading_file
      Tempfile.open(%w[test- .rb]) do |file|
        file.write("class Foo; end")
        file.rewind

        responses = run_server([
          Initialize.new(1),
          TextDocumentFormatting.new(2, "file://#{file.path}"),
          Shutdown.new(3)
        ])

        shape = LanguageServer::Request[[
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: [{ newText: :any }] },
          { id: 3, result: {} }
        ]]

        assert_operator(shape, :===, responses)
        assert_equal("class Foo\nend\n", responses.dig(1, :result, 0, :newText))
      end
    end

    def test_bogus_request
      assert_raises(ArgumentError) do
        run_server([{ method: "textDocument/bogus" }])
      end
    end

    def test_clean_shutdown
      responses = run_server([Initialize.new(1), Shutdown.new(2)])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    def test_file_that_does_not_exist
      responses = run_server([
        Initialize.new(1),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ])

      shape = LanguageServer::Request[[
        { id: 1, result: { capabilities: Hash } },
        { id: 2, result: :any },
        { id: 3, result: {} }
      ]]

      assert_operator(shape, :===, responses)
    end

    private

    def write(content)
      request = content.to_hash.merge(jsonrpc: "2.0").to_json
      "Content-Length: #{request.bytesize}\r\n\r\n#{request}"
    end

    def read(content)
      [].tap do |messages|
        while (headers = content.gets("\r\n\r\n"))
          source = content.read(headers[/Content-Length: (\d+)/i, 1].to_i)
          messages << JSON.parse(source, symbolize_names: true)
        end
      end
    end

    def run_server(messages, print_width: DEFAULT_PRINT_WIDTH, ignore_files: [])
      input = StringIO.new(messages.map { |message| write(message) }.join)
      output = StringIO.new

      LanguageServer.new(
        input: input,
        output: output,
        print_width: print_width,
        ignore_files: ignore_files
      ).run

      read(output.tap(&:rewind))
    end
  end
end
