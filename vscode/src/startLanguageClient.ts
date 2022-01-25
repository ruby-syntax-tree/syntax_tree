import { workspace, OutputChannel } from "vscode";
import { LanguageClient } from "vscode-languageclient/node";
import { promisify } from "util";
import { exec } from "child_process";

const promiseExec = promisify(exec);

async function startLocalClient(outputChannel: OutputChannel) {
  const rootFolder = workspace.workspaceFolders![0];
  const cwd = rootFolder.uri.fsPath;

  try {
    await promiseExec("bundle show syntax_tree", { cwd });
  } catch {
    outputChannel.appendLine("");
    outputChannel.appendLine("Error: Cannot find `syntax_tree` in Gemfile.");
    outputChannel.appendLine("Please add `syntax_tree` in your Gemfile and `bundle install`.");
    outputChannel.appendLine("");
    return null;
  }

  // In this case we're running inside a project, so we're going to attempt
  // to run stree with bundler.
  const run = {
    command: "bundle",
    args: ["exec", "stree", "lsp"],
    options: { cwd }
  };

  return new LanguageClient("Syntax Tree", { run, debug: run }, {
    documentSelector: [
      { scheme: "file", language: "ruby" },
    ],
    outputChannel
  });
}

function startGlobalClient(outputChannel: OutputChannel) {
  const run = { command: "stree", args: ["lsp"] }

  return new LanguageClient("Syntax Tree", { run, debug: run }, {
    documentSelector: [
      { scheme: "file", language: "ruby" },
    ],
    outputChannel
  });
}

async function startLanguageClient(outputChannel: OutputChannel) {
  if (workspace.workspaceFolders) {
    return await startLocalClient(outputChannel);
  } else {
    return startGlobalClient(outputChannel);
  }
}

export default startLanguageClient;
