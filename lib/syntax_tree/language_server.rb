# frozen_string_literal: true

require "cgi"
require "json"
require "uri"

require_relative "language_server/inlay_hints"

module SyntaxTree
  # Syntax Tree additionally ships with a language server conforming to the
  # language server protocol. It can be invoked through the CLI by running:
  #
  #     stree lsp
  #
  class LanguageServer
    attr_reader :input, :output, :print_width

    def initialize(
      input: $stdin,
      output: $stdout,
      print_width: DEFAULT_PRINT_WIDTH
    )
      @input = input.binmode
      @output = output.binmode
      @print_width = print_width
    end

    # rubocop:disable Layout/LineLength
    def run
      store =
        Hash.new do |hash, uri|
          filepath = CGI.unescape(URI.parse(uri).path)
          File.exist?(filepath) ? (hash[uri] = File.read(filepath)) : nil
        end

      while (headers = input.gets("\r\n\r\n"))
        source = input.read(headers[/Content-Length: (\d+)/i, 1].to_i)
        request = JSON.parse(source, symbolize_names: true)

        # stree-ignore
        case request
        in { method: "initialize", id: }
          store.clear
          write(id: id, result: { capabilities: capabilities })
        in { method: "initialized" }
          # ignored
        in { method: "shutdown" } # tolerate missing ID to be a good citizen
          store.clear
          write(id: request[:id], result: {})
          return
        in { method: "textDocument/didChange", params: { textDocument: { uri: }, contentChanges: [{ text: }, *] } }
          store[uri] = text
        in { method: "textDocument/didOpen", params: { textDocument: { uri:, text: } } }
          store[uri] = text
        in { method: "textDocument/didClose", params: { textDocument: { uri: } } }
          store.delete(uri)
        in { method: "textDocument/formatting", id:, params: { textDocument: { uri: } } }
          contents = store[uri]
          write(id: id, result: contents ? format(contents, uri.split(".").last) : nil)
        in { method: "textDocument/inlayHint", id:, params: { textDocument: { uri: } } }
          contents = store[uri]
          write(id: id, result: contents ? inlay_hints(contents) : nil)
        in { method: "syntaxTree/visualizing", id:, params: { textDocument: { uri: } } }
          write(id: id, result: PP.pp(SyntaxTree.parse(store[uri]), +""))
        in { method: %r{\$/.+} }
          # ignored
        else
          raise ArgumentError, "Unhandled: #{request}"
        end
      end
    end
    # rubocop:enable Layout/LineLength

    private

    def capabilities
      {
        documentFormattingProvider: true,
        inlayHintProvider: {
          resolveProvider: false
        },
        textDocumentSync: {
          change: 1,
          openClose: true
        }
      }
    end

    def format(source, extension)
      text = SyntaxTree::HANDLERS[".#{extension}"].format(source, print_width)

      [
        {
          range: {
            start: {
              line: 0,
              character: 0
            },
            end: {
              line: source.lines.size + 1,
              character: 0
            }
          },
          newText: text
        }
      ]
    rescue Parser::ParseError
      # If there is a parse error, then we're not going to return any formatting
      # changes for this source.
      nil
    end

    def inlay_hints(source)
      visitor = InlayHints.new
      SyntaxTree.parse(source).accept(visitor)
      visitor.hints
    rescue Parser::ParseError
      # If there is a parse error, then we're not going to return any inlay
      # hints for this source.
      []
    end

    def write(value)
      response = value.merge(jsonrpc: "2.0").to_json
      output.print("Content-Length: #{response.bytesize}\r\n\r\n#{response}")
      output.flush
    end

    def log(message)
      write(method: "window/logMessage", params: { type: 4, message: message })
    end
  end
end
