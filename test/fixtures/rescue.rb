%
begin
rescue
end
-
begin
rescue StandardError
end
%
begin
rescue => foo
  bar
end
%
begin
rescue Foo
  bar
end
%
begin
rescue Foo => foo
  bar
end
%
begin
rescue Foo, Bar
end
%
begin
rescue Foo, *Bar
end
%
begin
rescue Foo, Bar => foo
end
%
begin
rescue Foo, *Bar => foo
end
% # https://github.com/prettier/plugin-ruby/pull/1000
begin
rescue ::Foo
end
%
begin
rescue Foo
rescue Bar
end
%
begin
rescue Foo # comment
end
%
begin
rescue Foo, *Bar # comment
end
