%
begin
  foo
rescue Foo
  foo
rescue Bar
  foo
else
  foo
ensure
  foo
end
%
begin
  foo
rescue Foo
  foo
rescue Bar
  foo
end
%
begin
  foo
rescue Foo
  foo
rescue Bar
  foo
else
  foo
end
%
begin
  foo
ensure
  foo
end
%
begin
rescue StandardError
else # else
end
%
begin
ensure # ensure
end
%
begin
rescue # rescue
else # else
ensure # ensure
end
-
begin
rescue StandardError # rescue
else # else
ensure # ensure
end
