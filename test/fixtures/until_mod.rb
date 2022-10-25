%
bar until foo
%
barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr until foo
-
until foo
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
end
%
bar until foo # comment
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr until foo
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr until foo
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr until foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr until foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar until foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar until foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar until barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar until barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
  bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
}
