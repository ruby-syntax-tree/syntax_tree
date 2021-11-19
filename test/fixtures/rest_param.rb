%
def foo(*bar)
end
%
def foo(*)
end
%
def foo(
  *bar # comment
)
end
%
def foo(
  * # comment
)
end
