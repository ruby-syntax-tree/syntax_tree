# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.3.1] - 2022-04-22

### Changed

- `SyntaxTree::If` nodes inside of `SyntaxTree::Command` arguments should include a space before if they are flat.

## [2.3.0] - 2022-04-22

### Added

- [#52](https://github.com/ruby-syntax-tree/syntax_tree/pull/52) - `SyntaxTree::Formatter.format` for formatting an already parsed node.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - `if` and `unless` can now be transformed into ternaries if they're simple enough.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Nicely format call chains by one indentation.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Handle trailing operators in call chains when they are necessary because of comments.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Add some specialized formatting for Sorbet `sig` blocks to make them appear nicer.

### Changed

- [#53](https://github.com/ruby-syntax-tree/syntax_tree/pull/53) - Optional keyword arguments on method declarations have a value of `nil` now instead of `false`. This makes it easier to use the visitor.
- [#54](https://github.com/ruby-syntax-tree/syntax_tree/pull/54) - Flow control operators can now skip parentheses for simple, individual arguments. e.g., `break(1)` becomes `break 1`.
- [#54](https://github.com/ruby-syntax-tree/syntax_tree/pull/54) - Don't allow modifier conditionals to modify ternaries.
- [#55](https://github.com/ruby-syntax-tree/syntax_tree/pull/55) - Skip parentheses and brackets on arrays for flow control operators. e.g., `break([1, 2, 3])` becomes `break 1, 2, 3`.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Don't add parentheses to method calls if you don't need them.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Format comments on empty parameter sets. e.g., `def foo # bar` should keeps its comment.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - `%s[]` symbols on assignments should not indent to the next line.
- [#56](https://github.com/ruby-syntax-tree/syntax_tree/pull/56) - Empty hash and array literals with comments inside of them should be formatted correctly.

## [2.2.0] - 2022-04-19

### Added

- [#51](https://github.com/ruby-syntax-tree/syntax_tree/pull/51) - `SyntaxTree::Location` nodes now have pattern matching.
- [#51](https://github.com/ruby-syntax-tree/syntax_tree/pull/51) - `SyntaxTree::Heredoc` now have a `dedent` field that indicates the number of spaces to strip from the beginning of the string content.

### Changed

- [#51](https://github.com/ruby-syntax-tree/syntax_tree/pull/51) - `SyntaxTree::HshPtn` will now add a `then` if you use a bare `**` and `SyntaxTree::AryPtn` will do the same for a bare `*` on the end.
- [#51](https://github.com/ruby-syntax-tree/syntax_tree/pull/51) - `SyntaxTree::MLHSParen` now has a comma field in case a trailing comma has been added to a parenthesis destructuring, as in `((foo,))`.
- [#51](https://github.com/ruby-syntax-tree/syntax_tree/pull/51) - `SyntaxTree::FndPtn` has much improved parsing now.

## [2.1.1] - 2022-04-16

### Changed

- [#45](https://github.com/ruby-syntax-tree/syntax_tree/issues/45) - Fix parsing expressions like `foo.instance_exec(&T.must(block))`, where there are two `args_add_block` calls with a single `&`. Previously it was associating the `&` with the wrong block.
- [#47](https://github.com/ruby-syntax-tree/syntax_tree/pull/47) - Handle expressions like `not()`.
- [#48](https://github.com/ruby-syntax-tree/syntax_tree/pull/48) - Handle special call syntax with `::` operator.
- [#49](https://github.com/ruby-syntax-tree/syntax_tree/pull/49) - Handle expressions like `case foo; in {}; end`.
- [#50](https://github.com/ruby-syntax-tree/syntax_tree/pull/50) - Parsing expressions like `case foo; in **nil; end`.

## [2.1.0] - 2022-04-12

### Added

- The `SyntaxTree::Visitor` class now implements the visitor pattern for Ruby nodes.
- The `SyntaxTree::Visitor.visit_method(name)` method.
- Support for Ruby 2.7.
- Support for comments on `rescue` and `else` keywords.
- `SyntaxTree::Location` now additionally has `start_column` and `end_column`.
- The CLI now accepts content over STDIN for the `ast`, `check`, `debug`, `doc`, `format`, and `write` commands.

### Removed

- The missing hash value inlay hints have been removed.

## [2.0.1] - 2022-03-31

### Changed

- Move the `SyntaxTree.register_handler` method to the correct location.

## [2.0.0] - 2022-03-31

### Added

- The new `SyntaxTree.register_handler` hook for plugins.
- The new `--plugins=` option on the CLI.

### Changed

- Changed `SyntaxTree` from being a class to being a module. The parser functionality is moved into `SyntaxTree::Parser`.
- There is now a parent class for all of the nodes named `SyntaxTree::Node`.
- The `Implicits` class has been renamed to `InlayHints` to match the new LSP spec.

### Removed

- The disassembly code action has been removed to limit the scope of this project overall.

## [1.2.0] - 2022-01-09

### Added

- Support for Ruby 3.1 syntax, including: blocks without names, hash keys without values, endless methods without parentheses, and new argument forwarding.
- Support for pinned expressions and variables within pattern matching.
- Support endless ranges as the final argument to a `when` clause.

## [1.1.1] - 2021-12-09

### Added

- [#7](https://github.com/kddnewton/syntax_tree/issues/7) Better formatting for hashes and arrays that are values in hashes.
- [#9](https://github.com/kddnewton/syntax_tree/issues/9) Special handling for RSpec matchers when nesting `CommandCall` nodes.
- [#10](https://github.com/kddnewton/syntax_tree/issues/10) Force the maintaining of the modifier forms of conditionals and loops if the statement includes an assignment. Also, for the maintaining of the block form of conditionals and loops if the predicate includes an assignment.

## [1.1.0] - 2021-12-08

### Added

- Better handling for formatting files with errors.
- Colorize the output snippet using IRB.

## [1.0.0] - 2021-12-08

### Added

- The ability to "check" formatting by formatting the output of the first format.
- Comments can now be attached to the `case` keyword.
- Remove escaped forward slashes from regular expression literals when converting to `%r`.
- Allow arrays of `CHAR` nodes to be converted to `QWords` under certain conditions.
- Allow `HashLiteral` opening braces to have trailing comments.
- Add parentheses if `Yield` breaks onto multiple lines.
- Ensure all nodes that could have heredocs nested know about their end lines.
- Ensure comments on assignment after the `=` before the value keep their place.
- Trailing comments on parameters with no parentheses now do not force a break.
- Allow `ArrayLiteral` opening brackets to have trailing comments.
- Allow different line suffix nodes to have different priorities.
- Better support for encoding by properly reading encoding magic comments.
- Support singleton single-line method definitions.
- Support `stree-ignore` comments to ignore formatting nodes.
- Add special formatting for arrays of `VarRef` nodes whose sum width is greater than 2 * the maximum width.
- Better output formatting for the CLI.

### Changed

- Force a break if a block is attached to a `Command` or `CommandCall` node.
- Don't indent `CommandCall` arguments if they don't fit aligned.
- Force a break in `Call` nodes if there are comments on the receiver.
- Do not change block bounds if inside of a `Command` or `CommandCall` node.
- Handle empty parentheses inside method calls.
- Skip indentation for special array literals on assignment nodes.
- Ensure a final breakable is inserted when converting an `ArrayLiteral` to a `QSymbols`.
- Fix up the `doc_width` calculation for `CommandCall` nodes.
- Ensure parameters inside a lambda literal when there are no parentheses are grouped.
- Ensure when converting an `ArrayLiteral` to a `QWords` that the strings do not contain `[`.
- Stop looking for parent `Command` or `CommandCall` nodes in blocks once you hit `Statements`.
- Ensure nested `Lambda` nodes get their correct bounds.
- Ensure we do not change block bounds within control flow constructs.
- Ensure parentheses are added around keywords changing to their modifier forms.
- Allow conditionals to take modifier form if they are using the `then` keyword with a `VoidStmt`.
- `UntilMod` and `WhileMod` nodes that wrap a `Begin` should be forced into their modifier forms.
- Ensure `For` loops keep their trailing commas.
- Replicate content for `__END__` keyword exactly.
- Keep block `If`, `Unless`, `While`, and `Until` forms if there is an assignment in the predicate.
- Force using braces if the block is within the predicate of a conditional or loop.
- Allow for the possibility that `CommandCall` nodes might not have arguments.
- Explicitly handle `?"` so that it formats properly.
- Check that a block is within the predicate in a more relaxed way.
- Ensure the `Return` breaks with brackets and not parentheses.
- Ensure trailing comments on parameter declarations are consistent.
- Make `Command` and `CommandCall` aware that their arguments could exceed their normal expected bounds because of heredocs.
- Only unescape forward slashes in regular expressions if converting from slash bounds to `%r` bounds.
- Allow `When` nodes to grab trailing comments away from their statements lists.
- Allow flip-flop operators to be formatted correctly within `IfMod` and `UnlessMod` nodes.
- Allow `IfMod` and `UnlessMod` to know about heredocs moving their bounds.
- Properly handle breaking parameters when there are no parentheses.
- Properly handle trailing operators in call chains with attached comments.
- Force using braces if the block is within the predicate of a ternary.
- Properly handle trailing comments after a `then` operator on a `When` or `In` clause.
- Ensure nested `HshPtn` nodes use braces.
- Force using braces if the block is within a `Binary` within the predicate of a loop or conditional.
- Make sure `StringLiteral` and `StringEmbExpr` know that they can be extended by heredocs.
- Ensure `Int` nodes with preceding unary `+` get formatted properly.
- Properly handle byte-order mark column offsets at the beginnings of files.
- Ensure `Words`, `Symbols`, `QWords`, and `QSymbols` properly format when their contents contain brackets.
- Ensure ternaries being broken out into `if`...`else`...`end` get wrapped in parentheses if necessary.

### Removed

- The `AccessCtrl` node in favor of just formatting correctly when you hit a `Statements` node.
- The `MethodAddArg` node is removed in favor of an optional `arguments` field on `Call` and `FCall`.

## [0.1.0] - 2021-11-16

### Added

- 🎉 Initial release! 🎉

[unreleased]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.3.0...HEAD
[2.3.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.2.0...v2.3.0
[2.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.1.1...v2.2.0
[2.1.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.1.0...v2.1.1
[2.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.0.1...v2.1.0
[2.0.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.0.0...v2.0.1
[2.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v1.2.0...v2.0.0
[1.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/8aa1f5...v0.1.0
