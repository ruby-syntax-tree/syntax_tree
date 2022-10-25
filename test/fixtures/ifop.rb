%
foo ? bar : baz
%
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ? bar : baz
-
if foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
else
  baz
end
%
foo bar ? 1 : 2
%
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ? break : baz
-
foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo ?
  break :
  baz
%
barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz } ? bar : baz
-
if barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
     bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
   }
  bar
else
  baz
end
%
fooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz } ? bar : baz
-
if fooooooooooooooo ||
     barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
       bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
     end
  bar
else
  baz
end
