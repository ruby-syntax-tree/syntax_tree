# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

### Added

- The ability to "check" formatting by formatting the output of the first format.

### Changed

- Force a break if a block is attached to a `Command` or `CommandCall` node.
- Don't indent `CommandCall` arguments if they don't fit aligned.
- Force a break in `Call` nodes if there are comments on the receiver.
- Do not change block bounds if inside of a `Command` or `CommandCall` node.
- Handle empty parentheses inside method calls.

## [0.1.0] - 2021-11-16

### Added

- 🎉 Initial release! 🎉

[unreleased]: https://github.com/kddnewton/syntax_tree/compare/v0.1.0...HEAD
[0.1.0]: https://github.com/kddnewton/syntax_tree/compare/8aa1f5...v0.1.0
