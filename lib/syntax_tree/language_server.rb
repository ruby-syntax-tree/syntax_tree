# frozen_string_literal: true

require "cgi"
require "json"
require "uri"

require_relative "code_actions"
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
        source = input.read(headers[/Content-Length: (\d+)/i, 1].to_i)
        request = JSON.parse(source, symbolize_names: true)

        case request
        in { method: "initialize", id: }
          store.clear
          write(id: id, result: { capabilities: capabilities })
        in { method: "initialized" }
          # ignored
        in { method: "shutdown" }
          store.clear
          return
        in { method: "textDocument/codeAction", id:, params: { textDocument: { uri: }, range: { start: { line: } } } }
          write(id: id, result: code_actions(store[uri], line + 1))
        in { method: "textDocument/didChange", params: { textDocument: { uri: }, contentChanges: [{ text: }, *] } }
          store[uri] = text
        in { method: "textDocument/didOpen", params: { textDocument: { uri:, text: } } }
          store[uri] = text
        in { method: "textDocument/didClose", params: { textDocument: { uri: } } }
          store.delete(uri)
        in { method: "textDocument/formatting", id:, params: { textDocument: { uri: } } }
          write(id: id, result: [format(store[uri])])
        in { method: "syntaxTree/disasm", id:, params: { textDocument: { uri:, query: { line:, name: } } } }
          write(id: id, result: disasm(store[uri], line.to_i, name))
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
        codeActionProvider: { codeActionsKinds: ["disasm"] },
        documentFormattingProvider: true,
        textDocumentSync: { change: 1, openClose: true }
      }
    end

    def code_actions(source, line)
      actions = CodeActions.find(SyntaxTree.parse(source), line).actions
      log("Found #{actions.length} actions on line #{line}")

      actions.map(&:as_json)
    end

    def disasm(source, line, name)
      actions = CodeActions.find(SyntaxTree.parse(source), line).actions
      log("Disassembling #{name.inspect} on line #{line.inspect}")

      matched = actions.detect { |action| action.is_a?(CodeActions::DisasmAction) && action.node.name.value == name }
      return "Unable to find method: #{name}" unless matched

      # First, get an instruction sequence that encompasses the method that
      # we're going to disassemble. It will include the method declaration,
      # which will be the top instruction sequence.
      location = matched.node.location
      iseq = RubyVM::InstructionSequence.new(source[location.start_char...location.end_char])

      # Next, get the first child. We do this because the parent instruction
      # sequence is the method declaration, whereas the first child is the body
      # of the method, which is what we're interested in.
      method = nil
      iseq.each_child { |child| method = child }

      # Finally, return the disassembly as a string to the server, which will
      # serialize it to JSON and return it back to the client.
      method.disasm
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

    def log(message)
      write(method: "window/logMessage", params: { type: 4, message: message })
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
