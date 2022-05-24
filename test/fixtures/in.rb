%
case foo
in foo
end
%
case foo
in foo
  baz
end
%
case foo
in fooooooooooooooooooooooooooooooooooooo, barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
  baz
end
-
case foo
in [
     fooooooooooooooooooooooooooooooooooooo,
     barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
   ]
  baz
end
%
case foo
in foo
in bar
end
%
case foo
in bar
  # comment
end
%
case foo
in bar if baz
end
