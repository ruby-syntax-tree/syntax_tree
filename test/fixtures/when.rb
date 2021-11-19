%
case
when foo
end
%
case
when foo, bar
  baz
end
%
case
when foooooooooooooooooooooooooooooooooooo, barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
  baz
end
-
case
when foooooooooooooooooooooooooooooooooooo,
     barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
  baz
end
%
case
when foo then bar
end
-
case
when foo
  bar
end
%
case
when foooooooooooooooooo, barrrrrrrrrrrrrrrrrr, bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
end
-
case
when foooooooooooooooooo, barrrrrrrrrrrrrrrrrr,
     bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
end
%
case
when foo
when bar
end
%
case
when foo
else
end
