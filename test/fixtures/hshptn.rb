%
case foo
in bar:
end
%
case foo
in bar: bar
end
%
case foo
in bar:, baz:
end
%
case foo
in bar: bar, baz: baz
end
%
case foo
in **bar
end
%
case foo
in foo:, # comment1
   bar: # comment2
  baz
end
%
case foo
in Foo[bar:]
end
%
case foo
in Foo[bar: bar]
end
%
case foo
in Foo[bar:, baz:]
end
%
case foo
in Foo[bar: bar, baz: baz]
end
%
case foo
in Foo[**bar]
end
%
case foo
in {}
end
