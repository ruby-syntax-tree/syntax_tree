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
