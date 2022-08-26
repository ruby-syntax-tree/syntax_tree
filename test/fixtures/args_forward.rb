% # >= 2.7.3
def foo(...)
  bar(:baz, ...)
end
% # >= 3.1.0
def foo(foo, bar = baz, ...)
  bar(:baz, ...)
end
