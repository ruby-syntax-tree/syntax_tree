%
{}
%
{ bar: bar }
%
{ :bar => bar }
-
{ bar: bar }
%
{ :"bar" => bar }
-
{ bar: bar }
%
{ bar => bar, baz: baz }
-
{ bar => bar, :baz => baz }
%
{ bar => bar, "baz": baz }
-
{ bar => bar, :baz => baz }
%
{ bar: barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr, baz: bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
{
  bar: barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr,
  baz: bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
}
%
{
  # comment
}
% # >= 3.1.0
{ foo:, "bar" => "baz" }
