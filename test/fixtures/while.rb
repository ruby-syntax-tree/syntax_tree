%
while foo
end
%
while foo
  bar
end
-
bar while foo
%
while fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
end
%
foo = while bar do baz end
-
foo = (baz while bar)
%
while foo += 1
  foo
end
