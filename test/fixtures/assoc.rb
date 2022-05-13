%
{ foo: bar }
%
{ foo: barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr }
-
{
  foo:
    barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
}
%
{
  foo:
    bar
}
-
{ foo: bar }
%
{
  foo: [
    fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  ]
}
%
{
  foo: {
    fooooooooooooooooooooooooooooooooo: ooooooooooooooooooooooooooooooooooooooo
  }
}
%
{
  foo: -> do
    foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  end
}
%
{
  foo: %w[
    foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  ]
}
% # >= 3.1.0
{ foo: }
%
{ "foo": "bar" }
-
{ foo: "bar" }
%
{ "foo #{bar}": "baz" }
%
{ "foo=": "baz" }
