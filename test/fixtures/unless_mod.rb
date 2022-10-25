%
bar unless foo
%
barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr unless foo
-
unless foo
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
end
%
bar unless foo # comment
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr unless foo
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr unless foo
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr unless foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr unless foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar unless foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar unless foooooooooooooooooooooo ||
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
    bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
  end
%
foo = bar unless barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
-
foo = bar unless barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
  bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
}
