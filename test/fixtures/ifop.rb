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
tap { foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ? break : baz }
-
tap do
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ?
    break :
    baz
end
