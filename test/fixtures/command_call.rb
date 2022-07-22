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
%
foo.
  # comment
  bar baz
%
foo.bar baz ? qux : qaz
%
expect foo, bar.map { |i| { quux: bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz } }
-
expect foo,
       bar.map { |i|
         {
           quux:
             bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
         }
       }
%
expect(foo, bar.map { |i| {quux: bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz} })
-
expect(
  foo,
  bar.map do |i|
    {
      quux:
        bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
    }
  end
)
%
expect(foo.map { |i| { bar: i.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz } } ).to match(baz.map { |i| { bar: i.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz } })
-
expect(
  foo.map do |i|
    {
      bar:
        i.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
    }
  end
).to match(
  baz.map do |i|
    {
      bar:
        i.bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
    }
  end
)
