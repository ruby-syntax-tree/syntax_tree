%
bar if foo
%
barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr if foo
-
if foo
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
end
%
bar if foo # comment
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr if foo
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr if foo
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr if foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr if foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar if foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar if foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar if barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar if barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
  bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
}
