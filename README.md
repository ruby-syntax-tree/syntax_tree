<div align="center">
  <img alt="Syntax Tree" height="400px" src="./doc/logo.svg">
</div>

# Syntax Tree

[![Build Status](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml/badge.svg)](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/syntax_tree.svg)](https://rubygems.org/gems/syntax_tree)

Syntax Tree is fast Ruby parser built on top of the [prism](https://github.com/ruby/prism) Ruby parser. It is built with only standard library dependencies.

- [Installation](#installation)
- [CLI](#cli)
  - [check](#check)
  - [format](#format)
  - [write](#write)
  - [Configuration](#configuration)
  - [Globbing](#globbing)
- [Language server](#language-server)
- [Customization](#customization)
  - [Ignoring code](#ignoring-code)
  - [Plugins](#plugins)
- [Integration](#integration)
  - [Rake](#rake)
  - [RuboCop](#rubocop)
  - [Editors](#editors)
- [Contributing](#contributing)
- [License](#license)

## Installation

To install the gem globally, you can run:

```sh
gem install syntax_tree
```

To run the CLI with the gem installed globally, you would run:

```sh
stree version
```

If you're planning on using Syntax Tree within a project with `bundler`, add this line to your application's Gemfile:

```ruby
gem "syntax_tree"
```

And then execute:

```sh
bundle install
```

To run the CLI with the gem installed in your gem bundle, you would run:

```sh
bundle exec stree version
```

## CLI

Syntax Tree ships with the `stree` CLI, which can be used to format Ruby code. Below are listed all of the commands built into the CLI that you can use.

For many commands, file paths are accepted after the configuration options. For all of these commands, you can alternatively pass in content through STDIN or through the `-e` option to specify an inline script.

### check

This command is meant to be used in the context of a continuous integration or git hook. It checks each file given to make sure that it matches the expected format. It can be used to ensure unformatted content never makes it into a codebase.

```sh
stree check path/to/file.rb
```

For a file that matches the expected format, you will receive:

```
All files matched expected format.
```

If there are files with unformatted code, you will receive:

```
[warn] path/to/file.rb
The listed files did not match the expected format.
```

To change the print width that you are checking against, specify the `--print-width` option, as in:

```sh
stree check --print-width=100 path/to/file.rb
```

### format

This command will output the formatted version of each of the listed files to stdout. Importantly, it will not write that content back to the source files – for that, you want [`write`](#write).

```sh
stree format path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```ruby
1 + 1
```

To change the print width that you are formatting with, specify the `--print-width` option, as in:

```sh
stree format --print-width=100 path/to/file.rb
```

### write

This command will format the listed files and write that formatted version back to the source files. Note that this overwrites the original content, so be sure to be using a version control system.

```sh
stree write path/to/file.rb
```

This will list every file that is being formatted. It will output light gray if the file already matches the expected format. It will output in regular color if it does not.

```
path/to/file.rb 0ms
```

To change the print width that you are writing with, specify the `--print-width` option, as in:

```sh
stree write --print-width=100 path/to/file.rb
```

To ignore certain files from a glob (in order to make it easier to specify the filepaths), you can pass the `--ignore-files` option as an additional glob, as in:

```sh
stree write --ignore-files='db/**/*.rb' '**/*.rb'
```

### Configuration

All of the above commands accept additional configuration options. Those are:

- `--print-width=?` - The print width is the suggested line length that should be used when formatting the source. Note that this is not a hard limit like a linter. Instead, it is used as a guideline for how long lines _should_ be. For example, if you have the following code:

```ruby
foo do
  bar
end
```

In this case, the formatter will see that the block fits into the print width and will rewrite it using the `{}` syntax. This will actually make the line longer than originally written. This is why it is helpful to think of it as a suggestion, rather than a limit.
- `--preferred-quote=?` - The quote to use for string and character literals. This can be either `"` or `'`. It is "preferred" because in the case that the formatter encounters a string that contains interpolation or certain escape sequences, it will not attempt to change the quote style to avoid accidentally changing the semantic meaning of the code.
- `--[no-]trailing-comma` - Whether or not to add trailing commas to multiline array literals, hash literals, and method calls that can support trailing commas.

Any of the above CLI commands can also read configuration options from a `.streerc` file in the directory where the commands are executed. This should be a text file with each argument on a separate line.

```txt
--print-width=100
--trailing-comma
```

If this file is present, it will _always_ be used for CLI commands. The options in the `.streerc` file are passed to the CLI first, then the arguments from the command line. In the case of exclusive options (e.g. `--print-width`), this means that the command line options override what's in the config file. In the case of options that can take multiple inputs (e.g. `--plugins`), the effect is additive. That is, the plugins passed from the command line will be loaded _in addition to_ the plugins in the config file.

### Globbing

When running commands with `stree`, it's common to pass in lists of files. For example:

```sh
stree write 'lib/*.rb' 'test/*.rb'
```

The commands in the CLI accept any number of arguments. This means you _could_ pass `**/*.rb` (note the lack of quotes). This would make your shell expand out the file paths listed according to its own rules. (For example, [here](https://www.gnu.org/software/bash/manual/html_node/Filename-Expansion.html) are the rules for GNU bash.)

However, it's recommended to instead use quotes, which means that Ruby is responsible for performing the file path expansion instead. This ensures a consistent experience across different environments and shells. The globs must follow the Ruby-specific globbing syntax as specified in the documentation for [Dir](https://ruby-doc.org/core-3.1.1/Dir.html#method-c-glob).

Baked into this syntax is the ability to provide exceptions to file name patterns as well. For example, if you are in a Rails app and want to exclude files named `schema.rb` but write all other Ruby files, you can use the following syntax:

```shell
stree write "**/{[!schema]*,*}.rb"
```

## Language server

Syntax Tree additionally ships with a minimal language server conforming to the [language server protocol](https://microsoft.github.io/language-server-protocol/) that registers a formatter for the Ruby language. It can be invoked through the CLI by running:

```sh
stree lsp
```

There are related projects that configure and use this language server within IDEs. For example, to use this code with VSCode, see [ruby-syntax-tree/vscode-syntax-tree](https://github.com/ruby-syntax-tree/vscode-syntax-tree).

## Customization

There are multiple ways to customize Syntax Tree's behavior when parsing and formatting code. You can ignore certain sections of the source code, you can register plugins to provide custom formatting behavior, and you can register additional languages to be parsed and formatted.

### Ignoring code

To ignore a section of source code, you can use a special `# stree-ignore` comment. This comment should be placed immediately above the code that you want to ignore. For example:

```ruby
numbers = [
  10000,
  20000,
  30000
]
```

Normally the snippet above would be formatted as `numbers = [10_000, 20_000, 30_000]`. However, sometimes you want to keep the original formatting to improve readability or maintainability. In that case, you can put the ignore comment before it, as in:

```ruby
# stree-ignore
numbers = [
  10000,
  20000,
  30000
]
```

Now when Syntax Tree goes to format that code, it will copy the source code exactly as it is, including the newlines and indentation.

### Plugins

You can register additional customization that can flow through the same CLI with Syntax Tree's plugin system. When invoking the CLI, you pass through the list of plugins with the `--plugins` options to the commands that accept them. They should be a comma-delimited list. When the CLI first starts, it will require the files corresponding to those names.

To register plugins, define a file somewhere in your load path named `syntax_tree/my_plugin`. Then when invoking the CLI, you will pass `--plugins=my_plugin`. To require multiple, separate them by a comma. In this way, you can modify Syntax Tree however you would like. Some plugins ship with Syntax Tree itself. They are:

* `plugin/single_quotes` - This will change all of your string literals to use single quotes instead of the default double quotes.
* `plugin/trailing_comma` - This will put trailing commas into multiline array literals, hash literals, and method calls that can support trailing commas.

If you're using Syntax Tree as a library, you can require those files directly or manually pass those options to the formatter initializer through the `SyntaxTree::Options` class.

## Integration

Syntax Tree's goal is to seamlessly integrate into your workflow. To this end, it provides a couple of additional tools beyond the CLI and the Ruby library.

### Rake

Syntax Tree ships with the ability to define [rake](https://github.com/ruby/rake) tasks that will trigger runs of the CLI. To define them in your application, add the following configuration to your `Rakefile`:

```ruby
require "syntax_tree/rake"
SyntaxTree::Rake::CheckTask.new
SyntaxTree::Rake::WriteTask.new
```

These calls will define `rake stree:check` and `rake stree:write` (equivalent to calling `stree check` and `stree write` with the CLI respectively). You can configure them by either passing arguments to the `new` method or by using a block. In addition to the regular configuration options used for the formatter, there are a few additional options specific to the rake tasks.

#### `name`

If you'd like to change the default name of the rake task, you can pass that as the first argument, as in:

```ruby
SyntaxTree::Rake::WriteTask.new(:format)
```

#### `source_files`

If you wanted to configure Syntax Tree to check or write different files than the default (`lib/**/*.rb`), you can set the `source_files` field, as in:

```ruby
SyntaxTree::Rake::WriteTask.new do |t|
  t.source_files = FileList[%w[Gemfile Rakefile lib/**/*.rb test/**/*.rb]]
end
```

#### `ignore_files`

If you want to ignore certain file patterns when running the command, you can pass the `ignore_files` option. This will be checked with `File.fnmatch?` against each filepath that the command would be run against. For example:

```ruby
SyntaxTree::Rake::WriteTask.new do |t|
  t.source_files = "**/*.rb"
  t.ignore_files = "db/**/*.rb"
end
```

### RuboCop

RuboCop and Syntax Tree serve different purposes, but there is overlap with some of RuboCop's functionality. Syntax Tree provides a RuboCop configuration file to disable rules that are redundant with Syntax Tree. To use this configuration file, add the following snippet to the top of your project's `.rubocop.yml`:

```yaml
inherit_gem:
  syntax_tree: config/rubocop.yml
```

### Editors

* [Neovim](https://neovim.io/) - [neovim/nvim-lspconfig](https://github.com/neovim/nvim-lspconfig).
* [Vim](https://www.vim.org/) - [dense-analysis/ale](https://github.com/dense-analysis/ale).
* [VSCode](https://code.visualstudio.com/) - [ruby-syntax-tree/vscode-syntax-tree](https://github.com/ruby-syntax-tree/vscode-syntax-tree).
* [Emacs](https://www.gnu.org/software/emacs/) - [emacs-format-all-the-code](https://github.com/lassik/emacs-format-all-the-code).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby-syntax-tree/syntax_tree.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
