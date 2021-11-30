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
