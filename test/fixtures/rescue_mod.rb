%
bar rescue foo
-
begin
  bar
rescue StandardError
  foo
end
