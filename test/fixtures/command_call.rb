%
foo.bar baz
%
foo.bar barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr, bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
-
foo.bar barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr,
        bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
%
expect(foo).to receive(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo)
-
expect(foo).to receive(
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
)
%
expect(foo).not_to receive(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo)
-
expect(foo).not_to receive(
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
)
%
expect(foo).to_not receive(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo)
-
expect(foo).to_not receive(
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
)
%
foo.bar baz {}
%
foo.bar baz do
end
