%
until foo
end
%
until foo
  bar
end
-
bar until foo
%
until fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  bar
end
%
foo = until bar do baz end
-
foo = (baz until bar)
%
until foo += 1
  foo
end
%
until (foo += 1)
  foo
end
%
until true # comment1
  # comment2
end
%
until foooooooooooooooooooooo || barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
  something
end
-
until foooooooooooooooooooooo ||
        barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? do |bar|
          bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
        end
  something
end
%
until barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar| bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz }
  something
end
-
until barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.any? { |bar|
        bazzzzzzzzzzzzzzzzzzzzzzzzzzzzzzz
      }
  something
end
