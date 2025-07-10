%
tap { break }
%
tap { break foo }
%
tap { break foo, bar }
%
tap { break(foo) }
%
tap { break fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
tap do
  break(
    fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  )
end
%
tap { break(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo) }
-
tap do
  break(
    fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  )
end
%
tap { break (foo), bar }
%
tap do
  break(
    foo
    bar
  )
end
%
tap { break foo.bar :baz do |qux| qux end }
-
tap do
  break(
    foo.bar :baz do |qux|
      qux
    end
  )
end
%
tap { break :foo => "bar" }
