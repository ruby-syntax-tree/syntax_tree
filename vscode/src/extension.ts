"use strict";

import { ExtensionContext, TextDocumentContentProvider, Uri, commands, languages, window, workspace, ViewColumn } from "vscode";
import { LanguageClient } from "vscode-languageclient/node";
import { promisify } from "util";
import { exec } from "child_process";

const promiseExec = promisify(exec);

export function activate(context: ExtensionContext) {
  const scheme = "syntaxTree";

  let languageClient: LanguageClient | null = null;
  const outputChannel = window.createOutputChannel("Syntax Tree");

  context.subscriptions.push(
    commands.registerCommand(`${scheme}.start`, startClient),
    commands.registerCommand(`${scheme}.stop`, stopClient),
    commands.registerCommand(`${scheme}.restart`, restartClient),
    commands.registerCommand(`${scheme}.showOutputChannel`, showOutputChannel),
    commands.registerCommand(`${scheme}.visualize`, visualize),
    outputChannel
  );

  context.subscriptions.push(workspace.registerTextDocumentContentProvider(scheme, new class implements TextDocumentContentProvider {
		provideTextDocumentContent(uri: Uri): Promise<string> {
      if (languageClient) {
        return languageClient.sendRequest(`${scheme}/visualizing`, {
          textDocument: { uri: uri.path }
        });
      } else {
        return Promise.resolve("Language client not initialized.");
      }
		}
  }));

  return startClient();

  async function startLocalClient() {
    const rootFolder = workspace.workspaceFolders![0];
    const cwd = rootFolder.uri.fsPath;

    try {
      await promiseExec("bundle show syntax_tree", { cwd });
    } catch {
      outputChannel.appendLine("");
      outputChannel.appendLine("Error: Cannot find `syntax_tree` in Gemfile.");
      outputChannel.appendLine("Please add `syntax_tree` in your Gemfile and `bundle install`.");
      outputChannel.appendLine("");
      return;
    }

    // In this case we're running inside a project, so we're going to attempt
    // to run stree with bundler.
    const run = {
      command: "bundle",
      args: ["exec", "stree", "lsp"],
      options: { cwd }
    };

    languageClient = new LanguageClient("Syntax Tree", { run, debug: run }, {
      documentSelector: [
        { scheme: "file", language: "ruby" },
      ],
      outputChannel
    });
  }

  function startGlobalClient() {
    const run = { command: "stree", args: ["lsp"] }

    languageClient = new LanguageClient("Syntax Tree", { run, debug: run }, {
      documentSelector: [
        { scheme: "file", language: "ruby" },
      ],
      outputChannel
    });
  }

  async function startClient() {
    outputChannel.appendLine("Starting language server...");

    if (workspace.workspaceFolders) {
      await startLocalClient();
    } else {
      startGlobalClient();
    }

    if (languageClient) {
      context.subscriptions.push(languageClient.start());
    }
  }

  async function stopClient() {
    if (languageClient) {
      outputChannel.appendLine("Stopping language server...");
      await languageClient.stop();
    }
  }

  async function restartClient() {
    outputChannel.appendLine("Restarting language server...");
    await stopClient();
    await startClient();
  }

  function showOutputChannel() {
    outputChannel.show();
  }

  async function visualize() {
    const document = window.activeTextEditor?.document;

    if (languageClient && document && document.languageId === "ruby" && document.uri.scheme === "file") {
      const uri = Uri.parse(`${scheme}:${document.uri.toString()}`);

      const doc = await workspace.openTextDocument(uri);
      languages.setTextDocumentLanguage(doc, "plaintext");

			await window.showTextDocument(doc, ViewColumn.Beside, true);
    }
  }
}
