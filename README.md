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
  - [format](#format)
  - [write](#write)
- [Library](#library)
  - [SyntaxTree.read(filepath)](#syntaxtreereadfilepath)
  - [SyntaxTree.parse(source)](#syntaxtreeparsesource)
  - [SyntaxTree.format(source)](#syntaxtreeformatsource)
- [Nodes](#nodes)
  - [child_nodes](#child_nodes)
  - [Pattern matching](#pattern-matching)
  - [pretty_print(q)](#pretty_printq)
  - [to_json(*opts)](#to_jsonopts)
  - [format(q)](#formatq)
- [Visitor](#visitor)
  - [visit_method](#visit_method)
- [Language server](#language-server)
  - [textDocument/formatting](#textdocumentformatting)
  - [textDocument/inlayHints](#textdocumentinlayhints)
  - [syntaxTree/visualizing](#syntaxtreevisualizing)
- [Plugins](#plugins)
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

Syntax Tree ships with the `stree` CLI, which can be used to inspect and manipulate Ruby code. Below are listed all of the commands built into the CLI that you can use. Note that for all commands that operate on files, you can also pass in content through STDIN.

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

### format

This command will output the formatted version of each of the listed files. Importantly, it will not write that content back to the source files. It is meant to display the formatted version only.

```sh
stree format path/to/file.rb
```

For a file that contains `1 + 1`, you will receive:

```ruby
1 + 1
```

### write

This command will format the listed files and write that formatted version back to the source files. Note that this overwrites the original content, to be sure to be using a version control system.

```sh
stree write path/to/file.rb
```

This will list every file that is being formatted. It will output light gray if the file already matches the expected format. It will output in regular color if it does not.

```
path/to/file.rb 0ms
```

## Library

Syntax Tree can be used as a library to access the syntax tree underlying Ruby source code.

### SyntaxTree.read(filepath)

This function takes a filepath and returns a string associated with the content of that file. It is similar in functionality to `File.read`, except htat it takes into account Ruby-level file encoding (through magic comments at the top of the file).

### SyntaxTree.parse(source)

This function takes an input string containing Ruby code and returns the syntax tree associated with it. The top-level node is always a `SyntaxTree::Program`, which contains a list of top-level expression nodes.

### SyntaxTree.format(source)

This function takes an input string containing Ruby code, parses it into its underlying syntax tree, and formats it back out to a string.

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

## Language server

Syntax Tree additionally ships with a language server conforming to the [language server protocol](https://microsoft.github.io/language-server-protocol/). It can be invoked through the CLI by running:

```sh
stree lsp
```

By default, the language server is relatively minimal, mostly meant to provide a registered formatter for the Ruby language. However there are a couple of additional niceties baked in. There are related projects that configure and use this language server within IDEs. For example, to use this code with VSCode, see [ruby-syntax-tree/vscode-syntax-tree](https://github.com/ruby-syntax-tree/vscode-syntax-tree).

### textDocument/formatting

As mentioned above, the language server responds to formatting requests with the formatted document. It typically responds on the order of tens of milliseconds, so it should be fast enough for any IDE.

### textDocument/inlayHints

The language server also responds to the relatively new inlay hints request. This request allows the language server to define additional information that should exist in the source code as helpful hints to the developer. In our case we use it to display things like implicit parentheses. For example, if you had the following code:

```ruby
1 + 2 * 3
```

Implicity, the `2 * 3` is going to be executed first because the `*` operator has higher precedence than the `+` operator. However, to ease mental overhead, our language server includes small parentheses to make this explicit, as in:

```ruby
1 + ₍2 * 3₎
```

### syntaxTree/visualizing

The language server additionally includes this custom request to return a textual representation of the syntax tree underlying the source code of a file. Language server clients can use this to (for example) open an additional tab with this information displayed.

## Plugins

You can register additional languages that can flow through the same CLI with Syntax Tree's plugin system. To register a new language, call:

```ruby
SyntaxTree.register_handler(".mylang", MyLanguage)
```

In this case, whenever the CLI encounters a filepath that ends with the given extension, it will invoke methods on `MyLanguage` instead of `SyntaxTree` itself. To make sure your object conforms to each of the necessary APIs, it should implement:

* `MyLanguage.read(filepath)` - usually this is just an alias to `File.read(filepath)`, but if you need anything else that hook is here.
* `MyLanguage.parse(source)` - this should return the syntax tree corresponding to the given source. Those objects should implement the `pretty_print` interface.
* `MyLanguage.format(source)` - this should return the formatted version of the given source.

Below are listed all of the "official" plugins hosted under the same GitHub organization, which can be used as references for how to implement other plugins.

* [SyntaxTree::Haml](https://github.com/ruby-syntax-tree/syntax_tree-haml) for the [Haml template language](https://haml.info/).
* [SyntaxTree::JSON](https://github.com/ruby-syntax-tree/syntax_tree-json) for JSON.
* [SyntaxTree::RBS](https://github.com/ruby-syntax-tree/syntax_tree-rbs) for the [RBS type language](https://github.com/ruby/rbs).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby-syntax-tree/syntax_tree.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
