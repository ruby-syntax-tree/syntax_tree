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
%
if foo
  a ? b : c
end
%
if foo {}
end
%
if not a
  b
else
  c
end
%
if not(a)
  b
else
  c
end
%
(if foo then bar else baz end)
-
(
  if foo
    bar
  else
    baz
  end
)
%
if (x = x + 1).to_i
  x
end
%
if true # comment1
  # comment2
end
%
result =
  if false && val = 1
    "A"
  else
    "B"
  end
