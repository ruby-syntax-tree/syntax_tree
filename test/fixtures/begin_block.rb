%
BEGIN { foo }
%
BEGIN {
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
}
%
BEGIN {
  foo
}
-
BEGIN { foo }
%
BEGIN { foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
BEGIN {
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
}
%
BEGIN { # comment
  foo
}
%
BEGIN {
  # comment
  foo
}
