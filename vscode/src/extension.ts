"use strict";

import { ExtensionContext, commands, window } from "vscode";
import { LanguageClient } from "vscode-languageclient/node";

import Implicits from "./Implicits";
import startLanguageClient from "./startLanguageClient";
import Visualize from "./Visualize";

export function activate(context: ExtensionContext) {
  let languageClient: LanguageClient | null = null;
  const outputChannel = window.createOutputChannel("Syntax Tree");

  context.subscriptions.push(
    commands.registerCommand("syntaxTree.start", startLanguageServer),
    commands.registerCommand("syntaxTree.stop", stopLanguageServer),
    commands.registerCommand("syntaxTree.restart", restartLanguageServer),
    commands.registerCommand("syntaxTree.showOutputChannel", () => outputChannel.show()),
    outputChannel
  );

  return startLanguageServer();

  async function startLanguageServer() {
    outputChannel.appendLine("Starting language server...");
    languageClient = await startLanguageClient(outputChannel);

    if (languageClient) {
      context.subscriptions.push(languageClient.start());
      await languageClient.onReady();

      context.subscriptions.push(
        new Implicits(languageClient, outputChannel),
        new Visualize(languageClient, outputChannel)
      );
    }
  }

  async function stopLanguageServer() {
    if (languageClient) {
      outputChannel.appendLine("Stopping language server...");
      await languageClient.stop();
    }
  }

  async function restartLanguageServer() {
    outputChannel.appendLine("Restarting language server...");
    await stopLanguageServer();
    await startLanguageServer();
  }
}
