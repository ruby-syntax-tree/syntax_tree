# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [2.0.0] - 2022-03-30

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

[unreleased]: https://github.com/kddnewton/syntax_tree/compare/v1.2.0...HEAD
[1.2.0]: https://github.com/kddnewton/syntax_tree/compare/v1.1.1...v1.2.0
[1.1.1]: https://github.com/kddnewton/syntax_tree/compare/v1.1.0...v1.1.1
[1.1.0]: https://github.com/kddnewton/syntax_tree/compare/v1.0.0...v1.1.0
[1.0.0]: https://github.com/kddnewton/syntax_tree/compare/v0.1.0...v1.0.0
[0.1.0]: https://github.com/kddnewton/syntax_tree/compare/8aa1f5...v0.1.0
