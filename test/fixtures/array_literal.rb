%
[]
%
[foo, bar, baz]
%
[foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo, bar, baz]
-
[
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo,
  bar,
  baz
]
%
[
  foo,
  bar,
  baz
]
-
[foo, bar, baz]
%
fooooooooooooooooo = 1
[fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo]
-
fooooooooooooooooo = 1
[
  fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo,
  fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo,
  fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo, fooooooooooooooooo
]
%
[
  # comment
]
%
["foo"]
%
["foo", "bar"]
-
%w[foo bar]
%
["f", ?b]
-
%w[f b]
%
[
  "foo",
  "bar" # comment
]
%
["foo", "bar"] # comment
-
%w[foo bar] # comment
%
["foo", :bar]
%
["foo", "#{bar}"]
%
["foo", " bar "]
%
["foo", "bar\n"]
%
["foo", "bar]"]
%
[:foo]
%
[:foo, :bar]
-
%i[foo bar]
%
[
  :foo,
  :bar # comment
]
%
[:foo, :bar] # comment
-
%i[foo bar] # comment
%
[:foo, "bar"]
%
[:foo, :"bar"]
%
[foo, bar] # comment
