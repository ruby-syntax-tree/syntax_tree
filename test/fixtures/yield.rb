%
def foo
  yield foo
end
%
def foo
  yield(foo)
end
%
def foo
  yield foo, bar
end
%
def foo
  yield(foo, bar)
end
%
def foo
  yield foo # comment
end
%
def foo
  yield(foo) # comment
end
%
def foo
  yield( # comment
    foo
  )
end
