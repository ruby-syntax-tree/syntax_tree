%
bar while foo
%
barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr while foo
-
while foo
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
end
%
bar while foo # comment
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr while foo
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr while foo
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr while foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr while foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar while foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar while foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar while barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar while barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
  bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
}
