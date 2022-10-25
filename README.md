<div align="center">
  <img alt="Syntax Tree" height="400px" src="./doc/logo.svg">
</div>

# SyntaxTree

[![Build Status](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml/badge.svg)](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/syntax_tree.svg)](https://rubygems.org/gems/syntax_tree)

Syntax Tree is a suite of tools built on top of the internal CRuby parser. It provides the ability to generate a syntax tree from source, as well as the tools necessary to inspect and manipulate that syntax tree. It can be used to build formatters, linters, language servers, and more.

It is built with only standard library dependencies. It additionally ships with a plugin system so that you can build your own syntax trees from other languages and incorporate these tools.

- [Installation](#installation)
- [CLI](#cli)
  - [ast](#ast)
  - [check](#check)
  - [expr](#expr)
  - [format](#format)
  - [json](#json)
  - [match](#match)
  - [search](#search)
  - [write](#write)
  - [Configuration](#configuration)
  - [Globbing](#globbing)
- [Library](#library)
  - [SyntaxTree.read(filepath)](#syntaxtreereadfilepath)
  - [SyntaxTree.parse(source)](#syntaxtreeparsesource)
  - [SyntaxTree.format(source)](#syntaxtreeformatsource)
  - [SyntaxTree.search(source, query, &block)](#syntaxtreesearchsource-query-block)
- [Nodes](#nodes)
  - [child_nodes](#child_nodes)
  - [Pattern matching](#pattern-matching)
  - [pretty_print(q)](#pretty_printq)
  - [to_json(*opts)](#to_jsonopts)
  - [format(q)](#formatq)
  - [construct_keys](#construct_keys)
- [Visitor](#visitor)
  - [visit_method](#visit_method)
  - [BasicVisitor](#basicvisitor)
- [Language server](#language-server)
  - [textDocument/formatting](#textdocumentformatting)
  - [textDocument/inlayHint](#textdocumentinlayhint)
  - [syntaxTree/visualizing](#syntaxtreevisualizing)
- [Plugins](#plugins)
  - [Customization](#customization)
  - [Languages](#languages)
- [Integration](#integration)
  - [Rake](#rake)
  - [RuboCop](#rubocop)
  - [Editors](#editors)
- [Contributing](#contributing)
- [License](#license)

## Installation

Syntax Tree is both a command-line interface and a library. If you're only looking to use the command-line interface, then we recommend installing the gem globally, as in:

```sh
gem install syntax_tree
```

To run the CLI with the gem installed globally, you would run:

```sh
stree version
```

If you're planning on using Syntax Tree as a library within your own project, we recommend installing it as part of your gem bundle. First, add this line to your application's Gemfile:

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

Syntax Tree ships with the `stree` CLI, which can be used to inspect and manipulate Ruby code. Below are listed all of the commands built into the CLI that you can use.

For many commands, file paths are accepted after the configuration options. For all of these commands, you can alternatively pass in content through STDIN or through the `-e` option to specify an inline script.

### ast

This command will print out a textual representation of the syntax tree associated with each of the files it finds. To execute, run:

```sh
stree ast path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```
(program (statements (binary (int "1") + (int "1"))))
```

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

### expr

This command will output a Ruby case-match expression that would match correctly against the first expression of the input.

```sh
stree expr path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```ruby
SyntaxTree::Binary[
  left: SyntaxTree::Int[value: "1"],
  operator: :+,
  right: SyntaxTree::Int[value: "1"]
]
```

### format

This command will output the formatted version of each of the listed files. Importantly, it will not write that content back to the source files. It is meant to display the formatted version only.

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

### json

This command will output a JSON representation of the syntax tree that is functionally equivalent to the input. This is mostly used in contexts where you need to access the tree from JavaScript or serialize it over a network.

```sh
stree json path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```json
{
  "type": "program",
  "location": [1, 0, 1, 6],
  "statements": {
    "type": "statements",
    "location": [1, 0, 1, 6],
    "body": [
      {
        "type": "binary",
        "location": [1, 0, 1, 5],
        "left": {
          "type": "int",
          "location": [1, 0, 1, 1],
          "value": "1",
          "comments": []
        },
        "operator": "+",
        "right": {
          "type": "int",
          "location": [1, 4, 1, 5],
          "value": "1",
          "comments": []
        },
        "comments": []
      }
    ],
    "comments": []
  },
  "comments": []
}
```

### match

This command will output a Ruby case-match expression that would match correctly against the input.

```sh
stree match path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```ruby
SyntaxTree::Program[
  statements: SyntaxTree::Statements[
    body: [
      SyntaxTree::Binary[
        left: SyntaxTree::Int[value: "1"],
        operator: :+,
        right: SyntaxTree::Int[value: "1"]
      ]
    ]
  ]
]
```

### search

This command will search the given filepaths against the specified pattern to find nodes that match. The pattern is a Ruby pattern-matching expression that is matched against each node in the tree. It can optionally be loaded from a file if you specify a filepath as the pattern argument.

```sh
stree search VarRef path/to/file.rb
```

For a file that contains `Foo + Bar` you will receive:

```
path/to/file.rb:1:0: Foo + Bar
path/to/file.rb:1:6: Foo + Bar
```

If you put `VarRef` into a file instead (for example, `query.txt`), you would instead run:

```sh
stree search query.txt path/to/file.rb
```

Note that the output of the `match` CLI command creates a valid pattern that can be used as the input for this command.

### write

This command will format the listed files and write that formatted version back to the source files. Note that this overwrites the original content, to be sure to be using a version control system.

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

Any of the above CLI commands can also read configuration options from a `.streerc` file in the directory where the commands are executed.

This should be a text file with each argument on a separate line.

```txt
--print-width=100
--plugins=plugin/trailing_comma
```

If this file is present, it will _always_ be used for CLI commands. You can also pass options from the command line as in the examples above. The options in the `.streerc` file are passed to the CLI first, then the arguments from the command line. In the case of exclusive options (e.g. `--print-width`), this means that the command line options override what's in the config file. In the case of options that can take multiple inputs (e.g. `--plugins`), the effect is additive. That is, the plugins passed from the command line will be loaded _in addition to_ the plugins in the config file.

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

## Library

Syntax Tree can be used as a library to access the syntax tree underlying Ruby source code.

### SyntaxTree.read(filepath)

This function takes a filepath and returns a string associated with the content of that file. It is similar in functionality to `File.read`, except htat it takes into account Ruby-level file encoding (through magic comments at the top of the file).

### SyntaxTree.parse(source)

This function takes an input string containing Ruby code and returns the syntax tree associated with it. The top-level node is always a `SyntaxTree::Program`, which contains a list of top-level expression nodes.

### SyntaxTree.format(source)

This function takes an input string containing Ruby code, parses it into its underlying syntax tree, and formats it back out to a string. You can optionally pass a second argument to this method as well that is the maximum width to print. It defaults to `80`.

### SyntaxTree.search(source, query, &block)

This function takes an input string containing Ruby code, an input string containing a valid Ruby `in` clause expression that can be used to match against nodes in the tree (can be generated using `stree expr`, `stree match`, or `Node#construct_keys`), and a block. Each node that matches the given query will be yielded to the block. The block will receive the node as its only argument.

## Nodes

There are many different node types in the syntax tree. They are meant to be treated as immutable structs containing links to child nodes with minimal logic contained within their implementation. However, for the most part they all respond to a certain set of APIs, listed below.

### child_nodes

One of the easiest ways to descend the tree is to use the `child_nodes` function. It is implemented on every node type (leaf nodes return an empty array). If the goal is to simply walk through the tree, this is the easiest way to go.

```ruby
program = SyntaxTree.parse("1 + 1")
program.child_nodes.first.child_nodes.first
# => (binary (int "1") :+ (int "1"))
```

### Pattern matching

Pattern matching is another way to descend the tree which is more specific than using `child_nodes`. Using Ruby's built-in pattern matching, you can extract the same information but be as specific about your constraints as you like. For example, with minimal constraints:

```ruby
program = SyntaxTree.parse("1 + 1")
program => { statements: { body: [binary] } }
binary
# => (binary (int "1") :+ (int "1"))
```

Or, with more constraints on the types to ensure we're getting exactly what we expect:

```ruby
program = SyntaxTree.parse("1 + 1")
program => SyntaxTree::Program[statements: SyntaxTree::Statements[body: [SyntaxTree::Binary => binary]]]
binary
# => (binary (int "1") :+ (int "1"))
```

### pretty_print(q)

Every node responds to the `pretty_print` Ruby interface, which makes it usable by the `pp` library. You _can_ use this API manually, but it's mostly there for compatibility and not meant to be directly invoked. For example:

```ruby
pp SyntaxTree.parse("1 + 1")
# (program (statements (binary (int "1") + (int "1"))))
```

### to_json(*opts)

Every node responds to the `to_json` Ruby interface, which makes it usable by the `json` library. Much like `pretty_print`, you could use this API manually, but it's mostly used by `JSON` to dump the nodes to a serialized format. For example:

```ruby
program = SyntaxTree.parse("1 + 1")
program => { statements: { body: [{ left: }] } }
puts JSON.dump(left)
# {"type":"int","value":"1","loc":[1,0,1,1],"cmts":[]}
```

### format(q)

Every node responds to `format`, which formats the content nicely. The API mirrors that used by the `pretty_print` gem in that it accepts a formatter object and calls methods on it to generate its own internal representation of the text that will be outputted. Because of this, it's easier to not use this API directly and instead to call `SyntaxTree.format`. You _can_ however use this directly if you create the formatter yourself, as in:

```ruby
source = "1+1"
program = SyntaxTree.parse(source)
program => { statements: { body: [binary] } }

formatter = SyntaxTree::Formatter.new(source, [])
binary.format(formatter)

formatter.flush
formatter.output.join
# => "1 + 1"
```

### construct_keys

Every node responds to `construct_keys`, which will return a string that contains a Ruby pattern-matching expression that could be used to match against the current node. It's meant to be used in tooling and through the CLI mostly.

```ruby
program = SyntaxTree.parse("1 + 1")
puts program.construct_keys

# SyntaxTree::Program[
#   statements: SyntaxTree::Statements[
#     body: [
#       SyntaxTree::Binary[
#         left: SyntaxTree::Int[value: "1"],
#         operator: :+,
#         right: SyntaxTree::Int[value: "1"]
#       ]
#     ]
#   ]
# ]
```

## Visitor

If you want to operate over a set of nodes in the tree but don't want to walk the tree manually, the `Visitor` class makes it easy. `SyntaxTree::Visitor` is an implementation of the double dispatch visitor pattern. It works by the user defining visit methods that process nodes in the tree, which then call back to other visit methods to continue the descent. This is easier shown in code.

Let's say, for instance, that you wanted to find every place in source where you have an arithmetic problem between two integers (this is pretty contrived, but it's just for illustration). You could define a visitor that only explicitly visits the `SyntaxTree::Binary` node, as in:

```ruby
class ArithmeticVisitor < SyntaxTree::Visitor
  def visit_binary(node)
    if node in { left: SyntaxTree::Int, operator: :+ | :- | :* | :/, right: SyntaxTree::Int }
      puts "The result is: #{node.left.value.to_i.public_send(node.operator, node.right.value.to_i)}"
    end
  end
end

visitor = ArithmeticVisitor.new
visitor.visit(SyntaxTree.parse("1 + 1"))
# The result is: 2
```

With visitors, you only define handlers for the nodes that you need. You can find the names of the methods that you will need to define within the base visitor, as they're all aliased to the default behavior (visiting the child nodes). Note that when you define a handler for a node, you have to tell Syntax Tree how to walk further. In the example above, we don't need to go any further because we already know the child nodes are `SyntaxTree::Int`, so they can't possibly contain more `SyntaxTree::Binary` nodes. In other circumstances you may not know though, so you can either:

* call `super` (which will do the default and visit all child nodes)
* call `visit_child_nodes` manually
* call `visit(child)` with each child that you want to visit
* call nothing if you're sure you don't want to descend further

There are a couple of visitors that ship with Syntax Tree that can be used as examples. They live in the [lib/syntax_tree/visitor](lib/syntax_tree/visitor) directory.

### visit_method

When you're creating a visitor, it's very easy to accidentally mistype a visit method. Unfortunately, there's no way to tell Ruby to explicitly override a parent method, so it would then be easy to define a method that never gets called. To mitigate this risk, there's `Visitor.visit_method(name)`. This method accepts a symbol that is checked against the list of known visit methods. If it's not in the list, then an error will be raised. It's meant to be used like:

```ruby
class ArithmeticVisitor < SyntaxTree::Visitor
  visit_method def visit_binary(node)
    # ...
  end
end
```

This will only be checked once when the file is first required. If there is a typo in your method name (or the method no longer exists for whatever reason), you will receive an error like so:

```
~/syntax_tree/lib/syntax_tree/visitor.rb:46:in `visit_method': Invalid visit method: visit_binar (SyntaxTree::Visitor::VisitMethodError)
Did you mean?  visit_binary
               visit_in
               visit_ivar
	from (irb):2:in `<class:ArithmeticVisitor>'
	from (irb):1:in `<main>'
	from bin/console:8:in `<main>'
```

### BasicVisitor

When you're defining your own visitor, by default it will walk down the tree even if you don't define `visit_*` methods. This is to ensure you can define a subset of the necessary methods in order to only interact with the nodes you're interested in. If you'd like to change this default to instead raise an error if you visit a node you haven't explicitly handled, you can instead inherit from `BasicVisitor`.

```ruby
class MyVisitor < SyntaxTree::BasicVisitor
  def visit_int(node)
    # ...
  end
end
```

The visitor defined above will error out unless it's only visiting a `SyntaxTree::Int` node. This is useful in a couple of ways, e.g., if you're trying to define a visitor to handle the whole tree but it's currently a work-in-progress.

### WithEnvironment

The `WithEnvironment` module can be included in visitors to automatically keep track of local variables and arguments
defined inside each environment. A `current_environment` accessor is made availble to the request, allowing it to find
all usages and definitions of a local.

```ruby
class MyVisitor < Visitor
  include WithEnvironment

  def visit_ident(node)
    # find_local will return a Local for any local variables or arguments present in the current environment or nil if
    # the identifier is not a local
    local = current_environment.find_local(node)

    puts local.type # print the type of the local (:variable or :argument)
    puts local.definitions # print the array of locations where this local is defined
    puts local.usages # print the array of locations where this local occurs
  end
end
```

## Language server

Syntax Tree additionally ships with a language server conforming to the [language server protocol](https://microsoft.github.io/language-server-protocol/). It can be invoked through the CLI by running:

```sh
stree lsp
```

By default, the language server is relatively minimal, mostly meant to provide a registered formatter for the Ruby language. However there are a couple of additional niceties baked in. There are related projects that configure and use this language server within IDEs. For example, to use this code with VSCode, see [ruby-syntax-tree/vscode-syntax-tree](https://github.com/ruby-syntax-tree/vscode-syntax-tree).

### textDocument/formatting

As mentioned above, the language server responds to formatting requests with the formatted document. It typically responds on the order of tens of milliseconds, so it should be fast enough for any IDE.

### textDocument/inlayHint

The language server also responds to the relatively new inlay hints request. This request allows the language server to define additional information that should exist in the source code as helpful hints to the developer. In our case we use it to display things like implicit parentheses. For example, if you had the following code:

```ruby
1 + 2 * 3
```

Implicity, the `2 * 3` is going to be executed first because the `*` operator has higher precedence than the `+` operator. To ease mental overhead, our language server includes small parentheses to make this explicit, as in:

```ruby
1 + ₍2 * 3₎
```

### syntaxTree/visualizing

The language server additionally includes this custom request to return a textual representation of the syntax tree underlying the source code of a file. Language server clients can use this to (for example) open an additional tab with this information displayed.

## Plugins

You can register additional customization and additional languages that can flow through the same CLI with Syntax Tree's plugin system. When invoking the CLI, you pass through the list of plugins with the `--plugins` options to the commands that accept them. They should be a comma-delimited list. When the CLI first starts, it will require the files corresponding to those names.

### Customization

To register additional customization, define a file somewhere in your load path named `syntax_tree/my_plugin`. Then when invoking the CLI, you will pass `--plugins=my_plugin`. To require multiple, separate them by a comma. In this way, you can modify Syntax Tree however you would like. Some plugins ship with Syntax Tree itself. They are:

* `plugin/single_quotes` - This will change all of your string literals to use single quotes instead of the default double quotes.
* `plugin/trailing_comma` - This will put trailing commas into multiline array literals, hash literals, and method calls that can support trailing commas.

If you're using Syntax Tree as a library, you should require those files directly.

### Languages

To register a new language, call:

```ruby
SyntaxTree.register_handler(".mylang", MyLanguage)
```

In this case, whenever the CLI encounters a filepath that ends with the given extension, it will invoke methods on `MyLanguage` instead of `SyntaxTree` itself. To make sure your object conforms to each of the necessary APIs, it should implement:

* `MyLanguage.read(filepath)` - usually this is just an alias to `File.read(filepath)`, but if you need anything else that hook is here.
* `MyLanguage.parse(source)` - this should return the syntax tree corresponding to the given source. Those objects should implement the `pretty_print` interface.
* `MyLanguage.format(source)` - this should return the formatted version of the given source.

Below are listed all of the "official" language plugins hosted under the same GitHub organization, which can be used as references for how to implement other plugins.

* [bf](https://github.com/ruby-syntax-tree/syntax_tree-bf) for the [brainf*** language](https://esolangs.org/wiki/Brainfuck).
* [css](https://github.com/ruby-syntax-tree/syntax_tree-css) for the [CSS stylesheet language](https://www.w3.org/Style/CSS/).
* [haml](https://github.com/ruby-syntax-tree/syntax_tree-haml) for the [Haml template language](https://haml.info/).
* [json](https://github.com/ruby-syntax-tree/syntax_tree-json) for the [JSON notation language](https://www.json.org/).
* [rbs](https://github.com/ruby-syntax-tree/syntax_tree-rbs) for the [RBS type language](https://github.com/ruby/rbs).
* [xml](https://github.com/ruby-syntax-tree/syntax_tree-xml) for the [XML markup language](https://www.w3.org/XML/).

## Integration

Syntax Tree's goal is to seemlessly integrate into your workflow. To this end, it provides a couple of additional tools beyond the CLI and the Ruby library.

### Rake

Syntax Tree ships with the ability to define [rake](https://github.com/ruby/rake) tasks that will trigger runs of the CLI. To define them in your application, add the following configuration to your `Rakefile`:

```ruby
require "syntax_tree/rake_tasks"
SyntaxTree::Rake::CheckTask.new
SyntaxTree::Rake::WriteTask.new
```

These calls will define `rake stree:check` and `rake stree:write` (equivalent to calling `stree check` and `stree write` with the CLI respectively). You can configure them by either passing arguments to the `new` method or by using a block.

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

#### `print_width`

If you want to use a different print width from the default (80), you can pass that to the `print_width` field, as in:

```ruby
SyntaxTree::Rake::WriteTask.new do |t|
  t.print_width = 100
end
```

#### `plugins`

If you're running Syntax Tree with plugins (either your own or the pre-built ones), you can pass that to the `plugins` field, as in:

```ruby
SyntaxTree::Rake::WriteTask.new do |t|
  t.plugins = ["plugin/single_quotes"]
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

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby-syntax-tree/syntax_tree.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
