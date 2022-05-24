%
foo ? bar : baz
%
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ? bar : baz
-
if foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
else
  baz
end
%
foo bar ? 1 : 2
%
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ? break : baz
-
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ?
  break :
  baz
