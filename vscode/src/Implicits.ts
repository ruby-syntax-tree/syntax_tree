import { DecorationOptions, DecorationRangeBehavior, Disposable, OutputChannel, Range, TextEditor, TextEditorDecorationType, ThemeColor, window } from "vscode";
import { LanguageClient } from "vscode-languageclient/node";

type Implicit = { position: number, text: string };
type ImplicitsResponse = { before: Implicit[], after: Implicit[] };

class Implicits implements Disposable {
  private languageClient: LanguageClient;
  private outputChannel: OutputChannel;
  private decorationType: TextEditorDecorationType;

  constructor(languageClient: LanguageClient, outputChannel: OutputChannel) {
    this.languageClient = languageClient;
    this.outputChannel = outputChannel;
  
    const color = new ThemeColor("syntaxTree.implicits");
    this.decorationType = window.createTextEditorDecorationType({
      before: { color, fontStyle: "normal" },
      after: { color, fontStyle: "normal" },
      rangeBehavior: DecorationRangeBehavior.ClosedClosed
    });

    for (const editor of window.visibleTextEditors) {
      this.setImplicitsForEditor(editor);
    }
  }

  dispose() {
    this.decorationType.dispose();
  }

  async setImplicitsForEditor(editor: TextEditor) {
    if (editor.document.languageId != "ruby") {
      return;
    }

    this.outputChannel.appendLine("Requesting implicits");
    const implicits = await this.languageClient.sendRequest<ImplicitsResponse>("syntaxTree/implicits", {
      textDocument: { uri: editor.document.uri.toString() }
    });

    const decorations: DecorationOptions[] = [
      ...implicits.before.map(({ position, text: contentText }) => ({
        range: new Range(editor.document.positionAt(position), editor.document.positionAt(position)),
        renderOptions: { before: { contentText } }
      })),
      ...implicits.after.map(({ position, text: contentText }) => ({
        range: new Range(editor.document.positionAt(position), editor.document.positionAt(position)),
        renderOptions: { after: { contentText } }
      }))
    ];

    this.outputChannel.appendLine("Settings implicits");
    editor.setDecorations(this.decorationType, decorations);
  }
}

export default Implicits;
