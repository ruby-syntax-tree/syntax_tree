%
def foo.foo(bar)
  baz
end
%
def foo.foo bar
  baz
end
-
def foo.foo(bar)
  baz
end
%
def foo.foo(bar) # comment
end
%
def foo.foo()
end
%
def foo.foo() # comment
end
%
def foo.foo( # comment
)
end
%
def foo::foo
end
-
def foo.foo
end
