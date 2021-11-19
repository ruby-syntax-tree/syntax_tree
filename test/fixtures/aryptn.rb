%
case foo
in _, _
end
%
case foo
in bar, baz
end
%
case foo
in [bar]
end
%
case foo
in [bar, baz]
end
-
case foo
in bar, baz
end
%
case foo
in bar, *baz
end
%
case foo
in *bar, baz
end
%
case foo
in bar, *, baz
end
%
case foo
in *, bar, baz
end
%
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
%
case foo
in bar, baz if bar == baz
end
