# frozen_string_literal: true

require_relative "test_helper"
require "syntax_tree/language_server"

module SyntaxTree
  class LanguageServerTest < Minitest::Test
    class Initialize < Struct.new(:id)
      def to_hash
        { method: "initialize", id: id }
      end
    end

    class Shutdown < Struct.new(:id)
      def to_hash
        { method: "shutdown", id: id }
      end
    end

    class TextDocumentDidOpen < Struct.new(:uri, :text)
      def to_hash
        {
          method: "textDocument/didOpen",
          params: {
            textDocument: {
              uri: uri,
              text: text
            }
          }
        }
      end
    end

    class TextDocumentDidChange < Struct.new(:uri, :text)
      def to_hash
        {
          method: "textDocument/didChange",
          params: {
            textDocument: {
              uri: uri
            },
            contentChanges: [{ text: text }]
          }
        }
      end
    end

    class TextDocumentDidClose < Struct.new(:uri)
      def to_hash
        {
          method: "textDocument/didClose",
          params: {
            textDocument: {
              uri: uri
            }
          }
        }
      end
    end

    class TextDocumentFormatting < Struct.new(:id, :uri)
      def to_hash
        {
          method: "textDocument/formatting",
          id: id,
          params: {
            textDocument: {
              uri: uri
            }
          }
        }
      end
    end

    class TextDocumentInlayHint < Struct.new(:id, :uri)
      def to_hash
        {
          method: "textDocument/inlayHint",
          id: id,
          params: {
            textDocument: {
              uri: uri
            }
          }
        }
      end
    end

    class SyntaxTreeVisualizing < Struct.new(:id, :uri)
      def to_hash
        {
          method: "syntaxTree/visualizing",
          id: id,
          params: {
            textDocument: {
              uri: uri
            }
          }
        }
      end
    end

    def test_formatting
      messages = [
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "class Foo; end"),
        TextDocumentDidChange.new("file:///path/to/file.rb", "class Bar; end"),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        TextDocumentDidClose.new("file:///path/to/file.rb"),
        Shutdown.new(3)
      ]

      case run_server(messages)
      in [
           { id: 1, result: { capabilities: Hash } },
           { id: 2, result: [{ newText: new_text }] },
           { id: 3, result: {} }
         ]
        assert_equal("class Bar\nend\n", new_text)
      end
    end

    def test_inlay_hint
      messages = [
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", <<~RUBY),
          begin
            1 + 2 * 3
          rescue
          end
        RUBY
        TextDocumentInlayHint.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ]

      case run_server(messages)
      in [
           { id: 1, result: { capabilities: Hash } },
           { id: 2, result: hints },
           { id: 3, result: {} }
         ]
        assert_equal(3, hints.length)
      end
    end

    def test_visualizing
      messages = [
        Initialize.new(1),
        TextDocumentDidOpen.new("file:///path/to/file.rb", "1 + 2"),
        SyntaxTreeVisualizing.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ]

      case run_server(messages)
      in [
           { id: 1, result: { capabilities: Hash } },
           { id: 2, result: },
           { id: 3, result: {} }
         ]
        assert_equal(
          "(program (statements ((binary (int \"1\") + (int \"2\")))))\n",
          result
        )
      end
    end

    def test_reading_file
      Tempfile.open(%w[test- .rb]) do |file|
        file.write("class Foo; end")
        file.rewind

        messages = [
          Initialize.new(1),
          TextDocumentFormatting.new(2, "file://#{file.path}"),
          Shutdown.new(3)
        ]

        case run_server(messages)
        in [
             { id: 1, result: { capabilities: Hash } },
             { id: 2, result: [{ newText: new_text }] },
             { id: 3, result: {} }
           ]
          assert_equal("class Foo\nend\n", new_text)
        end
      end
    end

    def test_bogus_request
      assert_raises(ArgumentError) do
        run_server([{ method: "textDocument/bogus" }])
      end
    end

    def test_clean_shutdown
      messages = [Initialize.new(1), Shutdown.new(2)]

      case run_server(messages)
      in [{ id: 1, result: { capabilities: Hash } }, { id: 2, result: {} }]
        assert_equal(true, true)
      end
    end

    def test_file_that_does_not_exist
      messages = [
        Initialize.new(1),
        TextDocumentFormatting.new(2, "file:///path/to/file.rb"),
        Shutdown.new(3)
      ]

      case run_server(messages)
      in [
           { id: 1, result: { capabilities: Hash } },
           { id: 2, result: nil },
           { id: 3, result: {} }
         ]
        assert_equal(true, true)
      end
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

    def run_server(messages)
      input = StringIO.new(messages.map { |message| write(message) }.join)
      output = StringIO.new

      LanguageServer.new(input: input, output: output).run
      read(output.tap(&:rewind))
    end
  end
end
