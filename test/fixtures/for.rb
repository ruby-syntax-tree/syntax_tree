%
for foo in bar
end
%
for foo in bar
  foo
end
%
for foo in bar
  # comment
end
%
for foo, bar, baz in bar
end
%
for foo, bar, baz in bar
  foo
end
%
for foo, bar, baz in bar
  # comment
end
%
foo do
  # comment
  for bar in baz do
    bar
  end
end
-
foo do
  # comment
  for bar in baz
    bar
  end
end
