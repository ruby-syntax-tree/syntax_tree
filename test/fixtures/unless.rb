%
unless foo
end
%
unless foo
else
end
%
unless foo
  bar
end
-
bar unless foo
%
unless foo
  bar
else
end
%
foo = unless bar then baz end
-
foo = (baz unless bar)
%
unless foo += 1
  foo
end
%
unless (foo += 1)
  foo
end
