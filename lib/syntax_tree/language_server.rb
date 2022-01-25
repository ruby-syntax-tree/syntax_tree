# frozen_string_literal: true

require "cgi"
require "json"
require "uri"

require_relative "implicits"

class SyntaxTree
  class LanguageServer
    attr_reader :input, :output

    def initialize(input: STDIN, output: STDOUT)
      @input = input.binmode
      @output = output.binmode
    end

    def run
      store =
        Hash.new do |hash, uri|
          hash[uri] = File.binread(CGI.unescape(URI.parse(uri).path))
        end

      while headers = input.gets("\r\n\r\n")
        length = input.read(headers[/Content-Length: (\d+)/i, 1].to_i)
        request = JSON.parse(length, symbolize_names: true)

        case request
        in { method: "initialize", id: }
          store.clear
          write(id: id, result: { capabilities: capabilities })
        in { method: "initialized" }
          # ignored
        in { method: "shutdown" }
          store.clear
          return
        in { method: "textDocument/didChange", params: { textDocument: { uri: }, contentChanges: [{ text: }, *] } }
          store[uri] = text
        in { method: "textDocument/didOpen", params: { textDocument: { uri:, text: } } }
          store[uri] = text
        in { method: "textDocument/didClose", params: { textDocument: { uri: } } }
          store.delete(uri)
        in { method: "textDocument/formatting", id:, params: { textDocument: { uri: } } }
          write(id: id, result: [format(store[uri])])
        in { method: "syntaxTree/implicits", id:, params: { textDocument: { uri: } } }
          write(id: id, result: implicits(store[uri]))
        in { method: "syntaxTree/visualizing", id:, params: { textDocument: { uri: } } }
          output = []
          PP.pp(SyntaxTree.parse(store[uri]), output)
          write(id: id, result: output.join)
        in { method: %r{\$/.+} }
          # ignored
        else
          raise "Unhandled: #{request}"
        end
      end
    end

    private

    def capabilities
      {
        documentFormattingProvider: true,
        textDocumentSync: { change: 1, openClose: true },
      }
    end

    def format(source)
      {
        range: {
          start: { line: 0, character: 0 },
          end: { line: source.lines.size + 1, character: 0 }
        },
        newText: SyntaxTree.format(source)
      }
    end

    def implicits(source)
      implicits = Implicits.find(SyntaxTree.parse(source))
      serialize = ->(position, text) { { position: position, text: text } }

      {
        before: implicits.before.map(&serialize),
        after: implicits.after.map(&serialize)
      }
    rescue ParseError
    end

    def write(value)
      response = value.merge(jsonrpc: "2.0").to_json
      output.print("Content-Length: #{response.bytesize}\r\n\r\n#{response}")
      output.flush
    end
  end
end
