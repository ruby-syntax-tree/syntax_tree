# SyntaxTree

[![Build Status](https://github.com/kddnewton/syntax_tree/workflows/Main/badge.svg)](https://github.com/kddnewton/syntax_tree/actions)
[![Gem Version](https://img.shields.io/gem/v/syntax_tree.svg)](https://rubygems.org/gems/syntax_tree)

A fast ripper subclass used for parsing and formatting Ruby code.

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

Bug reports and pull requests are welcome on GitHub at https://github.com/kddnewton/syntax_tree. This project is intended to be a safe, welcoming space for collaboration, and contributors are expected to adhere to the [code of conduct](https://github.com/kddnewton/syntax_tree/blob/main/CODE_OF_CONDUCT.md).

## License

The gem is available as open source under the terms of the [MIT License](https://opensource.org/licenses/MIT).

## Code of Conduct

Everyone interacting in the syntax_tree project's codebases, issue trackers, chat rooms and mailing lists is expected to follow the [code of conduct](https://github.com/kddnewton/syntax_tree/blob/main/CODE_OF_CONDUCT.md).
