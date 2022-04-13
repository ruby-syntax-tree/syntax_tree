%
foo(&bar)
%
foo(
  &bar
)
-
foo(&bar)
%
foo(&bar.baz)
%
foo(&bar.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz)
-
foo(
  &bar.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
)
% # >= 3.1.0
def foo(&)
  bar(&)
end
% # https://github.com/ruby-syntax-tree/syntax_tree/issues/45
foo.instance_exec(&T.must(block))
