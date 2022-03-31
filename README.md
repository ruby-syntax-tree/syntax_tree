<div align="center">
  <img alt="Syntax Tree" height="400px" src="./doc/logo.svg">
</div>

# SyntaxTree

[![Build Status](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml/badge.svg)](https://github.com/ruby-syntax-tree/syntax_tree/actions/workflows/main.yml)
[![Gem Version](https://img.shields.io/gem/v/syntax_tree.svg)](https://rubygems.org/gems/syntax_tree)

A fast Ruby parser and formatter with only standard library dependencies.

## Installation

Add this line to your application's Gemfile:

```ruby
gem "syntax_tree"
```

And then execute:

    $ bundle install

Or install it yourself as:

    $ gem install syntax_tree

## Usage

From code:

```ruby
require "syntax_tree"

pp SyntaxTree.parse(source) # print out the AST
puts SyntaxTree.format(source) # format the AST
```

From the CLI:

```sh
$ stree ast program.rb
(program
  (statements
    ...
```

or

```sh
$ stree format program.rb
class MyClass
  ...
```

or

```sh
$ stree write program.rb
program.rb 1ms
```

## Development

After checking out the repo, run `bin/setup` to install dependencies. Then, run `rake test` to run the tests. You can also run `bin/console` for an interactive prompt that will allow you to experiment.

To install this gem onto your local machine, run `bundle exec rake install`. To release a new version, update the version number in `version.rb`, and then run `bundle exec rake release`, which will create a git tag for the version, push git commits and tags, and push the `.gem` file to [rubygems.org](https://rubygems.org).

## Contributing

Bug reports and pull requests are welcome on GitHub at https://github.com/ruby-syntax-tree/syntax_tree.

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).
