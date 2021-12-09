%
if foo
end
%
if foo
else
end
%
if foo
  bar
end
-
bar if foo
%
if foo
  bar
else
end
%
foo = if bar then baz end
-
foo = (baz if bar)
%
if foo += 1
  foo
end
%
if (foo += 1)
  foo
end
