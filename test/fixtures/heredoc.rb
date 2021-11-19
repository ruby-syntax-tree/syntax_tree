%
<<-FOO
  bar
FOO
%
<<-FOO
  bar
  #{baz}
FOO
%
<<-FOO
  foo
  #{<<-BAR}
  bar
BAR
FOO
%
<<-FOO
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  #{foo}
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
FOO
%
def foo
  <<~FOO.strip
    foo
  FOO
end
%
<<~FOO
  bar
FOO
%
<<~FOO
  bar
  #{baz}
FOO
%
<<~FOO
  foo
  #{<<~BAR}
    bar
  BAR
FOO
%
<<~FOO
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  #{foo}
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
FOO
%
def foo
  <<~FOO.strip
    foo
  FOO
end
%
call(foo, bar, baz, <<~FOO)
  foo
FOO
%
call(foo, bar, baz, <<~FOO, <<~BAR)
  foo
FOO
  bar
BAR
%
command foo, bar, baz, <<~FOO
  foo
FOO
%
command foo, bar, baz, <<~FOO, <<~BAR
  foo
FOO
  bar
BAR
%
command.call foo, bar, baz, <<~FOO
  foo
FOO
%
command.call foo, bar, baz, <<~FOO, <<~BAR
  foo
FOO
  bar
BAR
%
foo = <<~FOO.strip
  foo
FOO
%
foo(
  <<~FOO,
    foo
  FOO
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo:
    :bar
)
%
foo(<<~FOO
  foo
FOO
) { "foo" }
-
foo(<<~FOO) { "foo" }
  foo
FOO
