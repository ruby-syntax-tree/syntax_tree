%
until foo
end
%
until foo
  bar
end
-
bar until foo
%
until fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
end
%
foo = until bar do baz end
-
foo = (baz until bar)
%
until foo += 1
  foo
end
%
until (foo += 1)
  foo
end
