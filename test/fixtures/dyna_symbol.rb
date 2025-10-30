%
:'foo'
%
:"foo"
%
:'foo #{bar}'
%
:"foo #{bar}"
%
%s[foo #{bar}]
%
{ %s[foo] => bar }
-
{ foo: bar }
%
%s[
  foo
]
