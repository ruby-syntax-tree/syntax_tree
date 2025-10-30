# frozen_string_literal: true

require "cgi/escape"
require "json"
require "uri"

module SyntaxTree
  # A language server conforming to the language server protocol. It can be
  # invoked through the CLI by running:
  #
  #     stree lsp
  #
  # rubocop:disable Layout/LineLength
  class LSP
    def initialize(input = $stdin, output = $stdout, options: SyntaxTree.options, ignore_files: [])
      @input = input.binmode
      @output = output.binmode.tap { |io| io.sync = true }

      @options = options
      @ignore_files = ignore_files
    end

    def run
      store =
        Hash.new do |hash, uri|
          filepath = CGI.unescape(URI.parse(uri).path)
          hash[uri] = File.read(filepath) if File.exist?(filepath)
        end

      # stree-ignore
      while (headers = @input.gets("\r\n\r\n"))
        body = @input.read(Integer(headers[/Content-Length: (\d+)/i, 1]))

        case (request = JSON.parse(body, symbolize_names: true))[:method].to_sym
        when :"textDocument/didChange"
          request => { params: { textDocument: { uri: %r{\A.+//(.+\..+?)\z} => uri }, contentChanges: [{ text: }] } }
          store[uri] = text unless ignored?($1)
        when :"textDocument/didOpen"
          request => { params: { textDocument: { uri: %r{\A.+//(.+\..+?)\z} => uri, text: } } }
          store[uri] = text unless ignored?($1)
        when :"textDocument/didClose"
          request => { params: { textDocument: { uri: } } }
          store.delete(uri)
        when :"textDocument/formatting"
          request => { params: { textDocument: { uri: %r{\A.+//(.+(\..+?))\z} => uri } } }
          filepath = $1
          extension = $2

          write(
            request[:id],
            if (source = store[uri]) && !ignored?(filepath)
              begin
                [
                  {
                    newText: SyntaxTree.handler_for(extension).format(source, @options),
                    range: {
                      start: { line: 0, character: 0 },
                      end: { line: source.count("\n") + 1, character: 0 }
                    }
                  }
                ]
              rescue ParseError
              end
            end
          )
        when :initialize
          store.clear

          write(
            request[:id],
            {
              capabilities: {
                documentFormattingProvider: true,
                textDocumentSync: { change: 1, openClose: true }
              }
            }
          )
        when :shutdown
          store.clear

          write(request[:id], {}) and break
        when :initialized, :"textDocument/documentColor"
          # ignored
        else
          unless request[:method].start_with?("$/")
            raise ArgumentError, "Unknown method: #{request[:method]}"
          end
        end
      end
    end

    private

    def ignored?(filepath)
      @ignore_files.any? { |pattern| File.fnmatch(pattern, filepath) }
    end

    def write(id, result)
      response = { id: id, result: result, jsonrpc: "2.0" }.to_json
      @output.print("Content-Length: #{response.bytesize}\r\n\r\n#{response}")
    end
  end
  # rubocop:enable Layout/LineLength
end
