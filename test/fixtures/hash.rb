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
{ bar => bar, :"baz" => baz }
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
