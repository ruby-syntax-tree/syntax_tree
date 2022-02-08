import { commands, Disposable, languages, OutputChannel, ProviderResult, TextDocumentContentProvider, Uri, ViewColumn, window, workspace } from "vscode";
import { LanguageClient } from "vscode-languageclient/node";

class Disasm implements Disposable, TextDocumentContentProvider {
  // The client used to communicate with the language server.
  private readonly languageClient: LanguageClient;

  // The output channel used for logging for this class. It's given from the
  // main file so that it uses the same as the rest of the extension.
  private readonly outputChannel: OutputChannel;

  // The list of callbacks and objects that should be disposed when an instance
  // of Visualize is being disposed.
  private readonly disposables: Disposable[];

  constructor(languageClient: LanguageClient, outputChannel: OutputChannel) {
    this.languageClient = languageClient;
    this.outputChannel = outputChannel;
    this.disposables = [
      commands.registerCommand("syntaxTree.disasm", this.disasm),
      workspace.registerTextDocumentContentProvider("syntaxTree.disasm", this)
    ];
  }

  dispose() {
    this.disposables.forEach((disposable) => disposable.dispose());
  }

  provideTextDocumentContent(uri: Uri): ProviderResult<string> {
    this.outputChannel.appendLine("Requesting disassembly");

    const query: Record<string, string> = {};
    uri.query.split("&").forEach((pair) => {
      const [key, value] = pair.split("=");
      query[key] = value;
    });

    return this.languageClient.sendRequest("syntaxTree/disasm", { textDocument: { uri: uri.path, query } });
  }

  async disasm(line: number, name: string) {
    const document = window.activeTextEditor?.document;

    if (document && document.languageId === "ruby" && document.uri.scheme === "file") {
      const uri = Uri.parse(`syntaxTree.disasm:${document.uri.toString()}?line=${line}&name=${name}`);

      const doc = await workspace.openTextDocument(uri);
      languages.setTextDocumentLanguage(doc, "plaintext");

			await window.showTextDocument(doc, ViewColumn.Beside, true);
    }
  }
}

export default Disasm;
