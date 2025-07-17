# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](http://keepachangelog.com/en/1.0.0/) and this project adheres to [Semantic Versioning](http://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [6.3.0] - 2025-07-16

### Added

- The `--extension` command line option has been added to the CLI to specify what type of content is coming from stdin.
- The `--config` command line option has been added to the CLI to specify the path to the configuration file.

### Changed

- Fix formatting of character literals when single quotes is enabled.
- Pass ignore files option to the language server.
- Hash keys should remain unchanged when there are any omitted values in the hash.
- We now properly handle compilation errors in the parser.

## [6.2.0] - 2023-09-20

### Added

- Fix `WithScope` for destructured post arguments.

### Changed

- Always use `do`/`end` for multi-line lambdas.

## [6.1.1] - 2023-03-21

### Changed

- Fixed a bug where the call chain formatter was incorrectly looking at call messages.

## [6.1.0] - 2023-03-20

### Added

- The `stree ctags` command for generating ctags like `universal-ctags` or `ripper-tags` would.
- The `definedivar` YARV instruction has been added to match CRuby's implementation.
- We now generate better Sorbet RBI files for the nodes in the tree and the visitors.
- `SyntaxTree::Reflection.nodes` now includes the visitor method.

### Changed

- We now explicitly require `pp` in environments that need it.

## [6.0.2] - 2023-03-03

### Added

- The `WithScope` visitor mixin will now additionally report local variables defined through regular expression named captures.
- The `WithScope` visitor mixin now properly handles destructured splat arguments in required positions.

### Changed

- Fixed the AST output by adding blocks to `Command` and `CommandCall` nodes in the `FieldVisitor`.
- Fixed the location of lambda local variables (e.g., `->(; a) {}`).

## [6.0.1] - 2023-02-26

### Added

- The class declarations returned as the result of the indexing operation now have their superclass as a field. It is returned as an array of constants. If the superclass is anything other than a constant lookup, then it raises an error.

### Changed

- The `nesting` field on the results of the indexing operation is no longer a single flat array. Instead it is an array of arrays, where each array is a single nesting level. This more accurately reflects the nesting of the nodes in the tree. For example, `class Foo::Bar::Baz; end` would result in `[Foo, Bar, Baz]`, but that incorrectly implies that you can see constants at each of those levels. Now this would result in `[[Foo, Bar, Baz]]` to indicate that it can see either the top level or constants within the scope of `Foo::Bar::Baz` only.
- When formatting hashes that have omitted values and mixed hash rockets with labels, the formatting now maintains whichever delimiter was used in the source. This is because forcing the use of hash rockets with omitted values results in a syntax error.
- Handle the case where a bare hash is used after the `break`, `next`, or `return` keywords. Previously this would result in hash labels which is not valid syntax. Now it maintains the delimiters used in the source.
- The `<<` operator will now break on chained `<<` expressions. Previously it would always stay flat.

## [6.0.0] - 2023-02-10

### Added

- `SyntaxTree::BasicVisitor::visit_methods` has been added to allow you to check multiple visit methods inside of a block. There _was_ a method called `visit_methods` previously, but it was undocumented because it was meant as a private API. That method has been renamed to `valid_visit_methods`.
- `rake sorbet:rbi` has been added as a task within the repository to generate an RBI file corresponding to the nodes in the tree. This can be used to help aid consumers of Syntax Tree that are using Sorbet.
- `SyntaxTree::Reflection` has been added to allow you to get information about the nodes in the tree. It is not required by default, since it takes a small amount of time to parse `node.rb` and get all of the information.
- `SyntaxTree::Node#to_mermaid` has been added to allow you to generate a Mermaid diagram of the node and its children. This is useful for debugging and understanding the structure of the tree.
- `SyntaxTree::Translation` has been added as an experimental API to transform the Syntax Tree syntax tree into the syntax trees represented by the whitequark/parser and rubocop/rubocop-ast gems.
  - `SyntaxTree::Translation.to_parser(node, buffer)` will return a `Parser::AST::Node` object.
  - `SyntaxTree::Translation.to_rubocop_ast(node, buffer)` will return a `RuboCop::AST::Node` object.
- `SyntaxTree::index` and `SyntaxTree::index_file` have been added to allow you to get a list of all of the classes, modules, and methods defined in a given source string or file.
- Various convenience methods have been added:
  - `SyntaxTree::format_file` - which calls format with the result of reading the file
  - `SyntaxTree::format_node` - which formats the node directly
  - `SyntaxTree::parse_file` - which calls parse with the result of reading the file
  - `SyntaxTree::search_file` - which calls search with the result of reading the file
  - `SyntaxTree::Node#start_char` - which is the same as calling `node.location.start_char`
  - `SyntaxTree::Node#end_char` - which is the same as calling `node.location.end_char`
- `SyntaxTree::Assoc` nodes can now be formatted on their own without a parent hash node.
- `SyntaxTree::BlockVar#arg0?` has been added to check if a single required block parameter is present and would potentially be expanded.
- More experimental APIs have been added to the `SyntaxTree::YARV` module, including:
  - `SyntaxTree::YARV::ControlFlowGraph`
  - `SyntaxTree::YARV::DataFlowGraph`
  - `SyntaxTree::YARV::SeaOfNodes`

### Changed

#### Major changes

- *BREAKING* Updates to `WithEnvironment`:
  - The `WithEnvironment` module has been renamed to `WithScope`.
  - The `current_environment` method has been renamed to `current_scope`.
  - The `with_current_environment` method has been removed.
  - Previously scopes were always able to look up the tree, as in: `a = 1; def foo; a = 2; end` would see only a single `a` variable. That has been corrected.
  - Previously accessing variables from inside of blocks that were not shadowed would mark them as being local to the block only. This has been correct.
- *BREAKING* Lots of constants moved out of `SyntaxTree::Visitor` to just `SyntaxTree`:
  * `SyntaxTree::Visitor::FieldVisitor` is now `SyntaxTree::FieldVisitor`
  * `SyntaxTree::Visitor::JSONVisitor` is now `SyntaxTree::JSONVisitor`
  * `SyntaxTree::Visitor::MatchVisitor` is now `SyntaxTree::MatchVisitor`
  * `SyntaxTree::Visitor::MutationVisitor` is now `SyntaxTree::MutationVisitor`
  * `SyntaxTree::Visitor::PrettyPrintVisitor` is now `SyntaxTree::PrettyPrintVisitor`
- *BREAKING* Lots of constants are now autoloaded instead of required by default. This is only particularly relevant if you are in a forking environment and want to preload constants before forking for better memory usage with copy-on-write.
- *BREAKING* The `SyntaxTree::Statements#initialize` method no longer accepts a parser as the first argument. It now mirrors the other nodes in that it accepts its children and location. As a result, Syntax Tree nodes are now marshalable (and therefore can be sent over DRb). Previously the `Statements` node was not able to be marshaled because it held a reference to the parser.

#### Minor changes

- Many places where embedded documents (`=begin` to `=end`) were being treated as real comments have been fixed for formatting.
- Dynamic symbols in keyword pattern matching now have better formatting.
- Endless method definitions used to have a `SyntaxTree::BodyStmt` node that had any kind of node as its `statements` field. That has been corrected to be more consistent such that now going from `def_node.bodystmt.statements` always returns a `SyntaxTree::Statements` node, which is more consistent.
- We no longer assume that `fiddle` is able to be required, and only require it when it is actually needed.

#### Tiny changes

- Empty parameter nodes within blocks now have more accurate location information.
- Pinned variables have more correct location information now. (Previously the location was just around the variable itself, but it now includes the pin.)
- Array patterns in pattern matching now have more accurate location information when they are using parentheses with a constant present.
- Find patterns in pattern matching now have more correct location information for their `left` and `right` fields.
- Lots of nodes have more correct types in the comments on their attributes.
- The expressions `break foo.bar :baz do |qux| qux end` and `next fun foo do end` now correctly parses as a control-flow statement with a method call that has a block attached, as opposed to a control-flow statement with a block attached.
- The expression `self::a, b = 1, 2` would previously yield a `SyntaxTree::ConstPathField` node for the first element of the left-hand-side of the multiple assignment. Semantically this is incorrect, and we have fixed this to now be a `SyntaxTree::Field` node instead.

## [5.3.0] - 2023-01-26

### Added

- `#arity` has been added to `DefNode`, `BlockNode`, and `Params`. The method returns a range where the lower bound is the minimum and the upper bound is the maximum number of arguments that can be used to invoke that block/method definition.
- `#arity` has been added to `CallNode`, `Command`, `CommandCall`, and `VCall` nodes. The method returns the number of arguments included in the invocation. For splats, double splats, or argument forwards, this method returns `Float::INFINITY`.
- `SyntaxTree::index` and `SyntaxTree::index_file` APIs have been added to collect a list of classes, modules, and methods defined in a given source string or file, respectively. These APIs are experimental and subject to change.
- A `plugin/disable_auto_ternary` plugin has been added the disables the formatted that automatically changes permissable `if/else` clauses into ternaries.

### Changed

- Files are now only written from the CLI if the content of them changes, which should match watching files less chaotic.
- In the case that `rb_iseq_load` cannot be found, `Fiddle::DLError` is now rescued.
- Previously if there were invalid UTF-8 byte sequences after the `__END__` keyword the parser could potentially have crashed when parsing comments. This has been fixed.
- Previously there was special formatting for array literals that contained only variable references (either locals, method calls, or constants). For consistency, this has been removed and all array literals are now formatted the same way.

## [5.2.0] - 2023-01-04

### Added

- An experiment in evaluating compiled instruction sequences has been added to Syntax Tree. This is subject to change, so it will not be well documented or testing at the moment. It does not impact other functionality.

### Changed

- Empty parentheses on method calls will now be left in place. Previously they were left in place if the method being called looked like a constant. Now they are left in place for all method calls since the method name can mirror the name of a local variable, in which case the parentheses are required.

## [5.1.0] - 2022-12-28

### Added

- An experiment in working with instruction sequences has been added to Syntax Tree. This is subject to change, so it is not well documented or tested at the moment. It does not impact other functionality.
- You can now format at a different base layer of indentation. This is an optional third argument to `SyntaxTree::format`.

### Changed

- Support forwarding anonymous keyword arguments with `**`.
- The `BodyStmt` node now has a more correct location information.
- Ignore the `textDocument/documentColor` request coming into the language server to support clients that require that request be received.
- Do not attempt to convert `if..else` into ternaries if the predicate has a `Binary` node.
- Properly handle nested pattern matching when a rightward assignment is inside a `when` clause.

## [5.0.1] - 2022-11-10

### Changed

- Fix the plugin parsing on the CLI so that they are respected.

## [5.0.0] - 2022-11-09

### Added

- Every node now implements the `#copy(**)` method, which provides a copy of the node with the given attributes replaced.
- Every node now implements the `#===(other)` method, which checks if the given node matches the current node for all attributes except for comments and location.
- There is a new `SyntaxTree::Visitor::MutationVisitor` and its convenience method `SyntaxTree.mutation` which can be used to mutate a syntax tree. For details on how to use this visitor, check the README.

### Changed

- Nodes no longer have a `comments:` keyword on their initializers. By default, they initialize to an empty array. If you were previously passing comments into the initializer, you should now create the node first, then call `node.comments.concat` to add your comments.
- A lot of nodes have been folded into other nodes to make it easier to interact with the AST. This means that a lot of visit methods have been removed from the visitor and a lot of class definitions are no longer present. This also means that the nodes that received more function now have additional methods or fields to be able to differentiate them. Note that none of these changes have resulted in different formatting. The changes are listed below:
  - `IfMod`, `UnlessMod`, `WhileMod`, `UntilMod` have been folded into `IfNode`, `UnlessNode`, `WhileNode`, and `UntilNode`. Each of the nodes now have a `modifier?` method to tell if it was originally in the modifier form. Consequently, the `visit_if_mod`, `visit_unless_mod`, `visit_while_mod`, and `visit_until_mod` methods have been removed from the visitor.
  - `VarAlias` is no longer a node, and the `Alias` node has been renamed. They have been folded into the `AliasNode` node. The `AliasNode` node now has a `var_alias?` method to tell you if it is aliasing a global variable. Consequently, the `visit_var_alias` method has been removed from the visitor interface. If you were previously using this method, you should now use `visit_alias` instead.
  - `Yield0` is no longer a node, and the `Yield` node has been renamed. They has been folded into the `YieldNode` node. The `YieldNode` node can now have its `arguments` field be `nil`. Consequently, the `visit_yield0` method has been removed from the visitor interface. If you were previously using this method, you should now use `visit_yield` instead.
  - `FCall` is no longer a node, and the `Call` node has been renamed. They have been folded into the `CallNode` node. The `CallNode` node can now have its `receiver` and `operator` fields be `nil`. Consequently, the `visit_fcall` method has been removed from the visitor interface. If you were previously using this method, you should now use `visit_call` instead.
  - `Dot2` and `Dot3` are no longer nodes. Instead they have become a single new `RangeNode` node. This node looks the same as `Dot2` and `Dot3`, except that it additionally has an `operator` field that contains the operator that created the node. Consequently, the `visit_dot2` and `visit_dot3` methods have been removed from the visitor interface. If you were previously using these methods, you should now use `visit_range` instead.
  - `Def`, `DefEndless`, and `Defs` have been folded into the `DefNode` node. The `DefNode` node now has the `target` and `operator` fields which originally came from `Defs` which can both be `nil`. It also now has an `endless?` method on it to tell if the original node was found in the endless form. Finally the `bodystmt` field can now either be a `BodyStmt` as it was or any other kind of node since that was the body of the `DefEndless` node. The `visit_defs` and `visit_def_endless` methods on the visitor have therefore been removed.
  - `DoBlock` and `BraceBlock` have now been folded into a `BlockNode` node. The `BlockNode` node now has a `keywords?` method on it that returns true if the block was constructed with the `do`..`end` keywords. The `visit_do_block` and `visit_brace_block` methods on the visitor have therefore been removed and replaced with the `visit_block` method.
  - `Return0` is no longer a node, and the `Return` node has been renamed. They have been folded into the `ReturnNode` node. The `ReturnNode` node can now have its `arguments` field be `nil`. Consequently, the `visit_return0` method has been removed from the visitor interface. If you were previously using this method, you should now use `visit_return` instead.
- The `ArgsForward`, `Redo`, `Retry`, and `ZSuper` nodes no longer have `value` fields associated with them (which were always string literals corresponding to the keyword being used).
- The `Command` and `CommandCall` nodes now has `block` attributes on them. These attributes are used in the place where you would previously have had a `MethodAddBlock` structure. Where before the `MethodAddBlock` would have the command and block as its two children, you now just have one command node with the `block` attribute set to the `Block` node.
- Previously the formatting options were defined on an unfrozen hash called `SyntaxTree::Formatter::OPTIONS`. It was globally mutable, which made it impossible to reference from within a Ractor. As such, it has now been replaced with `SyntaxTree::Formatter::Options.new` which creates a new options object instance that can be modified without impacting global state. As a part of this change, formatting can now be performed from within a non-main Ractor. In order to check if the `plugin/single_quotes` plugin has been loaded, check if `SyntaxTree::Formatter::SINGLE_QUOTES` is defined. In order to check if the `plugin/trailing_comma` plugin has been loaded, check if `SyntaxTree::Formatter::TRAILING_COMMA` is defined.

## [4.3.0] - 2022-10-28

### Added

- [#183](https://github.com/ruby-syntax-tree/syntax_tree/pull/183) - Support TruffleRuby by eliminating internal pattern matching in some places and stopping some tests from running in other places.
- [#184](https://github.com/ruby-syntax-tree/syntax_tree/pull/184) - Remove internal pattern matching entirely.

### Changed

- [#183](https://github.com/ruby-syntax-tree/syntax_tree/pull/183) - Pattern matching works against dynamic symbols now.
- [#184](https://github.com/ruby-syntax-tree/syntax_tree/pull/184) - Exit with the correct exit status within the rake tasks.

## [4.2.0] - 2022-10-25

### Added

- [#182](https://github.com/ruby-syntax-tree/syntax_tree/pull/182) - The new `stree expr` CLI command will function similarly to the `stree match` CLI command except that it only outputs the first expression of the program.
- [#182](https://github.com/ruby-syntax-tree/syntax_tree/pull/182) - Added the `SyntaxTree::Pattern` class for compiling `in` expressions into procs.

### Changed

- [#182](https://github.com/ruby-syntax-tree/syntax_tree/pull/182) - Much more syntax is now supported by the search command.

## [4.1.0] - 2022-10-24

### Added

- [#180](https://github.com/ruby-syntax-tree/syntax_tree/pull/180) - The new `stree search` CLI command and the corresponding `SyntaxTree::Search` class for searching for a pattern against a given syntax tree.

## [4.0.2] - 2022-10-19

### Changed

- [#177](https://github.com/ruby-syntax-tree/syntax_tree/pull/177) - Fix up various other issues with the environment visitor addition.

## [4.0.1] - 2022-10-18

### Changed

- [#172](https://github.com/ruby-syntax-tree/syntax_tree/pull/172) - Use a refinement for `Symbol#name` addition so that other runtimes or tools don't get confused by its availability.
- [#173](https://github.com/ruby-syntax-tree/syntax_tree/pull/173) - Fix the `current_environment` usage to use the method instead of the instance variable.
- [#175](https://github.com/ruby-syntax-tree/syntax_tree/pull/175) - Update `prettier_print` requirement since v1.0.0 had a bug with `#breakable_return`.

## [4.0.0] - 2022-10-17

### Added

- [#169](https://github.com/ruby-syntax-tree/syntax_tree/pull/169) - You can now pass `--ignore-files` multiple times.
- [#157](https://github.com/ruby-syntax-tree/syntax_tree/pull/157) - We now support tracking local variable definitions throughout the visitor. This allows you to access scope information while visiting the tree.
- [#170](https://github.com/ruby-syntax-tree/syntax_tree/pull/170) - There is now an undocumented `STREE_FAST_FORMAT` environment variable checked when formatting. It has the effect of turning _off_ formatting call chains and ternaries in special ways. This improves performance quite a bit. I'm leaving it undocumented because ideally we just improve the performance as a whole. This is meant as a stopgap until we get there.

### Changed

- [#170](https://github.com/ruby-syntax-tree/syntax_tree/pull/170) - We now require at least version `1.0.0` of `prettier_print`. This is to take advantage of the first-class string support in the doc tree.
- [#170](https://github.com/ruby-syntax-tree/syntax_tree/pull/170) - Pattern matching has been removed from usage internal to this library (excluding the language server). This should hopefully enable runtimes that don't have pattern matching fully implemented yet (e.g., TruffleRuby) to run this gem.

## [3.6.3] - 2022-10-11

### Changed

- [#167](https://github.com/ruby-syntax-tree/syntax_tree/pull/167) - Change the error encountered when an `else` node does not have an associated `end` token to be a parse error.

## [3.6.2] - 2022-10-04

### Changed

- [#165](https://github.com/ruby-syntax-tree/syntax_tree/pull/165) - Conditionals (`if`/`unless`), loops (`for`/`while`/`until`) and lambdas all had issues when comments immediately succeeded the declaration of the node where the comment could potentially be dropped. That has now been fixed.
- [#166](https://github.com/ruby-syntax-tree/syntax_tree/pull/166) - Blocks can now be formatted even if they are the top node of the tree. Previously they were looking to their parent for some additional metadata, so we now handle the case where the parent is nil.

## [3.6.1] - 2022-09-28

### Changed

- [#161](https://github.com/ruby-syntax-tree/syntax_tree/pull/161) - Previously, we were checking if STDIN was a TTY to determine if there was content to be read. Instead, we now check if no filenames were passed, and in that case we attempt to read from STDIN. This should fix errors users were experiencing in non-TTY environments like CI.
- [#162](https://github.com/ruby-syntax-tree/syntax_tree/pull/162) - Parse errors shouldn't crash the language server anymore.

## [3.6.0] - 2022-09-19

### Added

- [#158](https://github.com/ruby-syntax-tree/syntax_tree/pull/158) - Support the ability to pass `--ignore-files` to the CLI and the Rake tasks to ignore a certain pattern of files.

## [3.5.0] - 2022-08-26

### Added

- [#148](https://github.com/ruby-syntax-tree/syntax_tree/pull/148) - Support Ruby 2.7.0 (previously we only supported back to 2.7.3).
- [#152](https://github.com/ruby-syntax-tree/syntax_tree/pull/152) - Support the `-e` inline script option for the `stree` CLI.

### Changed

- [#141](https://github.com/ruby-syntax-tree/syntax_tree/pull/141) - Use `q.format` for `SyntaxTree.format` so that the main node gets pushed onto the stack for checking parent nodes.
- [#147](https://github.com/ruby-syntax-tree/syntax_tree/pull/147) - Fix rightward assignment token management such that `in` and `=>` stay the same regardless of their context.

## [3.4.0] - 2022-08-19

### Added

- [#127](https://github.com/ruby-syntax-tree/syntax_tree/pull/127) - Allow the language server to handle other file extensions if it is activated for those extensions.
- [#133](https://github.com/ruby-syntax-tree/syntax_tree/pull/133) - Add documentation on supporting vim and neovim.

### Changed

- [#132](https://github.com/ruby-syntax-tree/syntax_tree/pull/132) - Provide better error messages when end quotes and end keywords are missing from tokens.
- [#134](https://github.com/ruby-syntax-tree/syntax_tree/pull/134) - Ensure the correct `end` keyword is getting removed by `begin..rescue` clauses.
- [#137](https://github.com/ruby-syntax-tree/syntax_tree/pull/137) - Better support regular expressions with no ending token.

## [3.3.0] - 2022-08-02

### Added

- [#123](https://github.com/ruby-syntax-tree/syntax_tree/pull/123) - Allow the rake tasks to configure print width.
- [#125](https://github.com/ruby-syntax-tree/syntax_tree/pull/125) - Add support for an `.streerc` file in the current working directory to configure the CLI.

## [3.2.1] - 2022-07-22

### Changed

- [#119](https://github.com/ruby-syntax-tree/syntax_tree/pull/119) - If there are conditionals in the assignment we cannot convert it to the modifier form. There was a bug where it would stop checking for assignment nodes if there were any optional child nodes.

## [3.2.0] - 2022-07-19

### Added

- [#116](https://github.com/ruby-syntax-tree/syntax_tree/pull/116) - Pass the `--print-width` option in the CLI to the language server.

## [3.1.0] - 2022-07-19

### Added

- [#115](https://github.com/ruby-syntax-tree/syntax_tree/pull/115) - Support the `--print-width` option in the CLI for the actions that support it.

## [3.0.1] - 2022-07-15

### Changed

- [#112](https://github.com/ruby-syntax-tree/syntax_tree/pull/112) - Fix parallel CLI execution by not short-circuiting with the `||` operator.

## [3.0.0] - 2022-07-04

### Changed

- [#102](https://github.com/ruby-syntax-tree/syntax_tree/issues/102) - Handle requests to the language server for files that do not yet exist on disk.

### Removed

- [#108](https://github.com/ruby-syntax-tree/syntax_tree/pull/108) - Remove old inlay hints code.

## [2.9.0] - 2022-07-04

### Added

- [#106](https://github.com/ruby-syntax-tree/syntax_tree/pull/106) - Add inlay hint support to match the LSP specification.

## [2.8.0] - 2022-06-21

### Added

- [#95](https://github.com/ruby-syntax-tree/syntax_tree/pull/95) - The `HeredocEnd` node has been added which effectively results in the ability to determine the location of the ending of a heredoc from source.
- [#99](https://github.com/ruby-syntax-tree/syntax_tree/pull/99) - The LSP now allows you to pass the same configuration options as the other CLI commands which allows formatting to be modified in the VSCode extension.
- [#100](https://github.com/ruby-syntax-tree/syntax_tree/pull/100) - The LSP now explicitly responds to the shutdown request so that VSCode never deadlocks.

### Changed

- [#96](https://github.com/ruby-syntax-tree/syntax_tree/pull/96) - The CLI now runs in parallel by default. There is a worker created for each processor on the running machine (as determined by `Etc.nprocessors`).
- [#97](https://github.com/ruby-syntax-tree/syntax_tree/pull/97) - Syntax Tree now handles the case where `DidYouMean` is not available for whatever reason, as well as handles the newer `detailed_message` API for errors.

## [2.7.1] - 2022-05-25

### Added

- [#92](https://github.com/ruby-syntax-tree/syntax_tree/pull/92) - (Internal) Drastically increase test coverage, including many more tests for the language server and the CLI.

### Changed

- [#87](https://github.com/ruby-syntax-tree/syntax_tree/pull/87) - Don't convert quotes on strings if it would result in more escapes.
- [#91](https://github.com/ruby-syntax-tree/syntax_tree/pull/91) - Always use `[]` with array patterns. There are just too many edge cases where you have to use them anyway. This simplifies the look and makes it more consistent.
- [#92](https://github.com/ruby-syntax-tree/syntax_tree/pull/92) - Remodel the currently shipped plugins such that they're modifying an options hash instead of overriding methods. This should make it easier for other plugins to reference the already loaded plugins, e.g., the RBS plugin referencing the quotes.
- [#92](https://github.com/ruby-syntax-tree/syntax_tree/pull/92) - Fix up the language server inlay hints to continue walking the tree once a pattern is found. This should increase useability.

## [2.7.0] - 2022-05-19

### Added

- [#88](https://github.com/ruby-syntax-tree/syntax_tree/pull/88) - Provide a `SyntaxTree::BasicVisitor` that has no visit methods implemented.

### Changed

- [#90](https://github.com/ruby-syntax-tree/syntax_tree/pull/90) - Provide better formatting for `SyntaxTree::AryPtn` when its nested inside a `SyntaxTree::RAssign`.

## [2.6.0] - 2022-05-16

### Added

- [#74](https://github.com/ruby-syntax-tree/syntax_tree/pull/74) - Add Rake test to run check and format commands.
- [#83](https://github.com/ruby-syntax-tree/syntax_tree/pull/83) - Add a trailing commas plugin.
- [#84](https://github.com/ruby-syntax-tree/syntax_tree/pull/84) - Handle lambda block-local variables.

### Changed

- [#85](https://github.com/ruby-syntax-tree/syntax_tree/pull/85) - Better handle trailing operators on command calls.

## [2.5.0] - 2022-05-13

### Added

- [#79](https://github.com/ruby-syntax-tree/syntax_tree/pull/79) - Support an optional `maxwidth` second argument to `SyntaxTree.format`.

### Changed

- [#77](https://github.com/ruby-syntax-tree/syntax_tree/pull/77) - Correct the pattern for checking if a dynamic symbol can be converted into a label as a hash key.
- [#72](https://github.com/ruby-syntax-tree/syntax_tree/pull/72) - Disallow conditionals with `not` without parentheses in the predicate from turning into a ternary.

## [2.4.1] - 2022-05-10

- [#73](https://github.com/ruby-syntax-tree/syntax_tree/pull/73) - Fix nested hash patterns from accidentally adding a `then` to their output.

## [2.4.0] - 2022-05-07

### Added

- [#65](https://github.com/ruby-syntax-tree/syntax_tree/pull/65) - Add a rubocop config at `config/rubocop.yml` that we can ship with the gem so folks can inherit from it to get their styling correct.
- [#65](https://github.com/ruby-syntax-tree/syntax_tree/pull/65) - Improve hash pattern formatting by a lot - multiple lines are now not so ugly.
- [#62](https://github.com/ruby-syntax-tree/syntax_tree/issues/62) - Add `options` as a method on `SyntaxTree::RegexpLiteral`, add it to pattern matching, and describe it using the `SyntaxTree::Visitor::FieldVisitor` class.
- [#69](https://github.com/ruby-syntax-tree/syntax_tree/pull/69) - The `construct_keys` option has been added to every `SyntaxTree::Node` descendant. This allows building a pattern match expression that can be used later. It is meant as a reflection API, not necessarily something that should be eval'd.
- [#69](https://github.com/ruby-syntax-tree/syntax_tree/pull/69) - You can now call `stree json` to get a JSON representation of your syntax tree.
- [#69](https://github.com/ruby-syntax-tree/syntax_tree/pull/69) - You can now call `stree match` to get a Ruby pattern matching expression to match against the given input.

### Changed

- [#69](https://github.com/ruby-syntax-tree/syntax_tree/pull/69) - Fixed a long-standing bug with pretty-print where if certain things were required in different orders you could end up with a bug in `PP` when calling pretty-print with a confusing error referring to inspect keys.
- [#69](https://github.com/ruby-syntax-tree/syntax_tree/pull/69) - `SyntaxTree.read` can now handle an empty file.

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

[unreleased]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.2.0...HEAD
[6.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.1.1...v6.2.0
[6.1.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.1.0...v6.1.1
[6.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.0.2...v6.1.0
[6.0.2]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.0.1...v6.0.2
[6.0.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v6.0.0...v6.0.1
[6.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v5.3.0...v6.0.0
[5.3.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v5.2.0...v5.3.0
[5.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v5.1.0...v5.2.0
[5.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v5.0.1...v5.1.0
[5.0.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v5.0.0...v5.0.1
[5.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.3.0...v5.0.0
[4.3.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.2.0...v4.3.0
[4.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.1.0...v4.2.0
[4.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.0.2...v4.1.0
[4.0.2]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.0.1...v4.0.2
[4.0.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v4.0.0...v4.0.1
[4.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.6.3...v4.0.0
[3.6.3]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.6.2...v3.6.3
[3.6.2]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.6.1...v3.6.2
[3.6.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.6.0...v3.6.1
[3.6.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.5.0...v3.6.0
[3.5.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.4.0...v3.5.0
[3.4.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.3.0...v3.4.0
[3.3.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.2.1...v3.3.0
[3.2.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.2.0...v3.2.1
[3.2.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.1.0...v3.2.0
[3.1.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.0.1...v3.1.0
[3.0.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v3.0.0...v3.0.1
[3.0.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.9.0...v3.0.0
[2.9.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.8.0...v2.9.0
[2.8.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.7.1...v2.8.0
[2.7.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.7.0...v2.7.1
[2.7.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.6.0...v2.7.0
[2.6.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.5.0...v2.6.0
[2.5.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.4.1...v2.5.0
[2.4.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.4.0...v2.4.1
[2.4.0]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.3.1...v2.4.0
[2.3.1]: https://github.com/ruby-syntax-tree/syntax_tree/compare/v2.3.0...v2.3.1
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
