# frozen_string_literal: true

require_relative "test_helper"
require "json"

module SyntaxTree
  # stree-ignore
  class LSPTest < Minitest::Test
    def test_formatting
      responses = run_server([
        request_initialize(1),
        request_open("file:///path/to/file.rb", "class Foo; end"),
        request_change("file:///path/to/file.rb", "class Bar; end"),
        request_formatting(2, "file:///path/to/file.rb"),
        request_close("file:///path/to/file.rb"),
        request_shutdown(3)
      ])

      new_text = nil
      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: [{ newText: new_text }] },
          { id: 3, result: {} }
        ]
      end

      assert_equal("class Bar\nend\n", new_text)
    end

    def test_formatting_ignore
      responses = run_server([
        request_initialize(1),
        request_open("file:///path/to/file.rb", "class Foo; end"),
        request_formatting(2, "file:///path/to/file.rb"),
        request_shutdown(3)
      ], ignore_files: ["path/**/*.rb"])

      result = nil
      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: },
          { id: 3, result: {} }
        ]
      end

      assert_nil(result)
    end

    def test_formatting_failure
      responses = run_server([
        request_initialize(1),
        request_open("file:///path/to/file.rb", "<>"),
        request_formatting(2, "file:///path/to/file.rb"),
        request_shutdown(3)
      ])

      result = nil
      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: },
          { id: 3, result: {} }
        ]
      end

      assert_nil(result)
    end

    def test_formatting_print_width
      contents = "#{"a" * 40} + #{"b" * 40}\n"
      responses = run_server([
        request_initialize(1),
        request_open("file:///path/to/file.rb", contents),
        request_formatting(2, "file:///path/to/file.rb"),
        request_close("file:///path/to/file.rb"),
        request_shutdown(3)
      ], print_width: 100)

      new_text = nil
      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: [{ newText: new_text }] },
          { id: 3, result: {} }
        ]
      end

      assert_equal(contents, new_text)
    end

    def test_reading_file
      Tempfile.open(%w[test- .rb]) do |file|
        file.write("class Foo; end")
        file.rewind

        responses = run_server([
          request_initialize(1),
          request_formatting(2, "file://#{file.path}"),
          request_shutdown(3)
        ])

        new_text = nil
        assert_pattern do
          responses => [
            { id: 1, result: { capabilities: Hash } },
            { id: 2, result: [{ newText: new_text }] },
            { id: 3, result: {} }
          ]
        end

        assert_equal("class Foo\nend\n", new_text)
      end
    end

    def test_bogus_request
      assert_raises(ArgumentError) do
        run_server([{ method: "textDocument/bogus" }])
      end
    end

    def test_clean_shutdown
      responses = run_server([request_initialize(1), request_shutdown(2)])

      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: {} }
        ]
      end
    end

    def test_file_that_does_not_exist
      responses = run_server([
        request_initialize(1),
        request_formatting(2, "file:///path/to/file.rb"),
        request_shutdown(3)
      ])

      assert_pattern do
        responses => [
          { id: 1, result: { capabilities: Hash } },
          { id: 2, result: _ },
          { id: 3, result: {} }
        ]
      end
    end

    private

    def request_initialize(id)
      { method: "initialize", id: id }
    end

    def request_shutdown(id)
      { method: "shutdown", id: id }
    end

    def request_open(uri, text)
      {
        method: "textDocument/didOpen",
        params: { textDocument: { uri: uri, text: text } }
      }
    end

    def request_change(uri, text)
      {
        method: "textDocument/didChange",
        params: {
          textDocument: { uri: uri },
          contentChanges: [{ text: text }]
        }
      }
    end

    def request_close(uri)
      {
        method: "textDocument/didClose",
        params: { textDocument: { uri: uri } }
      }
    end

    def request_formatting(id, uri)
      {
        method: "textDocument/formatting",
        id: id,
        params: { textDocument: { uri: uri } }
      }
    end

    def run_server(messages, print_width: :default, ignore_files: [])
      input = StringIO.new
      output = StringIO.new

      messages.each do |message|
        request = JSON.generate(message.merge(jsonrpc: "2.0"))
        input.write("Content-Length: #{request.bytesize}\r\n\r\n#{request}")
      end

      input.rewind
      options = SyntaxTree.options(print_width: print_width)
      LSP.new(input, output, options: options, ignore_files: ignore_files).run
      output.rewind

      results = []
      while (headers = output.gets("\r\n\r\n"))
        body = output.read(Integer(headers[/Content-Length: (\d+)/i, 1]))
        results << JSON.parse(body, symbolize_names: true)
      end
      results
    end
  end
end
