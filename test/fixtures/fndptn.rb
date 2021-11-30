%
case foo
in [*, bar, *]
end
%
case foo
in [*, bar, baz, qux, *]
end
%
case foo
in [*foo, bar, *]
end
%
case foo
in [*, bar, *baz]
end
%
case foo
in [*foo, bar, *baz]
end
%
case foo
in Foo[*, bar, *]
end
%
case foo
in Foo[*, bar, baz, qux, *]
end
%
case foo
in Foo[*foo, bar, *]
end
%
case foo
in Foo[*, bar, *baz]
end
%
case foo
in Foo[*foo, bar, *baz]
end
