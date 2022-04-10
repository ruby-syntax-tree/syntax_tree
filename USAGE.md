# SyntaxTree Usage

## Utilizing SyntaxTree's API

Aside from providing a formatted view of AST nodes, SyntaxTree also provides access to information on each AST node.

This quick tutorial will show you some common APIs in SyntaxTree. Keep in mind this is only a fraction of methods available to use and you can find more in the [official documentation](https://ruby-syntax-tree.github.io/syntax_tree/).

Alright! Let's attain the `:+` operator in the following Ruby source code:

```ruby
require "syntax_tree"
tree = SyntaxTree.parse("puts 1+1")
```

Everything with a block of code inside of it has a list of statements represented by a `SyntaxTree::Statements` node.

```ruby
statements = tree.statements
# => (statements (command (ident "puts") (args ((binary (int "1") :+ (int "1"))))))
```

Let's extract the first (and only) statement of our source code that is a `SyntaxTree::Command` node, representing the `puts` method call.

```ruby
puts_command = statements.body.first
# => (command (ident "puts") (args ((binary (int "1") :+ (int "1")))))
```

Using `#child_nodes` we can get an array of child nodes for any particular `SyntaxTree::Node`. In this case, the command node's child nodes are the method name and the arguments.

We are only interested in the arguments, so we can use the instance method `#arguments` to access the `Syntax::Args` node directly.

```ruby
puts_command.child_nodes
# => [(ident "puts"), (args ((binary (int "1") :+ (int "1"))))]

args = puts_command.arguments
# => (args ((binary (int "1") :+ (int "1"))))
```

The `#parts` method returns an array of arguments. In this case, we want the first argument to access the `SyntaxTree::Binary` node.

```ruby
binary = args.parts.first
# => [(binary (int "1") :+ (int "1"))]
```

A `SyntaxTree::Binary` node represents an expression with two operands and an operator in between, and we can get the operator using the instance method `#operator`.

```ruby
binary.operator
# => :+
```

Lastly, each node has a `SyntaxTree::Location` object, providing information on the row and column of the node.

```ruby
binary.location
# => #<SyntaxTree::Location:0x0000000104a32898 @end_char=8, @end_line=1, @start_char=5, @start_line=1>
```

## Visiting Nodes

SyntaxTree allows you to perform additional operations on nodes through the [visitor pattern](https://en.wikipedia.org/wiki/Visitor_pattern).
