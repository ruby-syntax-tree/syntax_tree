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
    attr_reader :input, :output

    def initialize(input: $stdin, output: $stdout)
      @input = input.binmode
      @output = output.binmode
    end

    def run
      store =
        Hash.new do |hash, uri|
          hash[uri] = File.binread(CGI.unescape(URI.parse(uri).path))
        end

      while (headers = input.gets("\r\n\r\n"))
        source = input.read(headers[/Content-Length: (\d+)/i, 1].to_i)
        request = JSON.parse(source, symbolize_names: true)

        case request
        in { method: "initialize", id: }
          store.clear
          write(id: id, result: { capabilities: capabilities })
        in method: "initialized"
          # ignored
        in method: "shutdown"
          store.clear
          return
        in {
             method: "textDocument/didChange",
             params: { textDocument: { uri: }, contentChanges: [{ text: }, *] }
           }
          store[uri] = text
        in {
             method: "textDocument/didOpen",
             params: { textDocument: { uri:, text: } }
           }
          store[uri] = text
        in {
             method: "textDocument/didClose", params: { textDocument: { uri: } }
           }
          store.delete(uri)
        in {
             method: "textDocument/formatting",
             id:,
             params: { textDocument: { uri: } }
           }
          write(id: id, result: [format(store[uri])])
        in {
             method: "textDocument/inlayHints",
             id:,
             params: { textDocument: { uri: } }
           }
          write(id: id, result: inlay_hints(store[uri]))
        in {
             method: "syntaxTree/visualizing",
             id:,
             params: { textDocument: { uri: } }
           }
          write(id: id, result: PP.pp(SyntaxTree.parse(store[uri]), +""))
        in method: %r{\$/.+}
          # ignored
        else
          raise ArgumentError, "Unhandled: #{request}"
        end
      end
    end

    private

    def capabilities
      {
        documentFormattingProvider: true,
        textDocumentSync: {
          change: 1,
          openClose: true
        }
      }
    end

    def format(source)
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
        newText: SyntaxTree.format(source)
      }
    end

    def inlay_hints(source)
      inlay_hints = InlayHints.find(SyntaxTree.parse(source))
      serialize = ->(position, text) { { position: position, text: text } }

      {
        before: inlay_hints.before.map(&serialize),
        after: inlay_hints.after.map(&serialize)
      }
    rescue Parser::ParseError
      # If there is a parse error, then we're not going to return any inlay
      # hints for this source.
    end

    def write(value)
      response = value.merge(jsonrpc: "2.0").to_json
      output.print("Content-Length: #{response.bytesize}\r\n\r\n#{response}")
      output.flush
    end
  end
end
