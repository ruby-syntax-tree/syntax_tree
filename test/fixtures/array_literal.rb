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
["foo"]
%
["foo", "bar"]
-
%w[foo bar]
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
