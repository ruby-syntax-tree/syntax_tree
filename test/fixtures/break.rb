%
break
%
break foo
%
break foo, bar
%
break(foo)
%
break fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
-
break(
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
)
%
break(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo)
-
break(
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
)
%
break (foo), bar
%
break(
  foo
  bar
)
%
break foo.bar :baz do |qux| qux end
