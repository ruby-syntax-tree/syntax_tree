%
case foo
in []
end
%
case foo
in [] then
end
-
case foo
in []
end
%
case foo
in * then
end
-
case foo
in [*]
end
%
case foo
in _, _
end
-
case foo
in [_, _]
end
%
case foo
in bar, baz
end
-
case foo
in [bar, baz]
end
%
case foo
in [bar]
end
%
case foo
in [bar]
in [baz]
end
%
case foo
in [bar, baz]
end
%
case foo
in bar, *baz
end
-
case foo
in [bar, *baz]
end
%
case foo
in *bar, baz
end
-
case foo
in [*bar, baz]
end
%
case foo
in bar, *, baz
end
-
case foo
in [bar, *, baz]
end
%
case foo
in *, bar, baz
end
-
case foo
in [*, bar, baz]
end
%
case foo
in Constant[bar]
end
%
case foo
in Constant(bar)
end
-
case foo
in Constant[bar]
end
%
case foo
in Constant[bar, baz]
end
%
case foo
in bar, [baz, _] => qux
end
-
case foo
in [bar, [baz, _] => qux]
end
%
case foo
in bar, baz if bar == baz
end
-
case foo
in [bar, baz] if bar == baz
end
