%
def foo(req)
end
%
def foo(req1, req2)
end
%
def foo(optl = foo)
end
%
def foo(optl1 = foo, optl2 = bar)
end
%
def foo(*)
end
%
def foo(*rest)
end
% # >= 2.7.3
def foo(...)
end
%
def foo(*, post)
end
%
def foo(*, post1, post2)
end
%
def foo(key:)
end
%
def foo(key1:, key2:)
end
%
def foo(key: foo)
end
%
def foo(key1: foo, key2: bar)
end
%
def foo(**)
end
%
def foo(**kwrest)
end
%
def foo(&block)
end
%
def foo(req1, req2, optl = foo, *rest, key1:, key2: bar, **kwrest, &block)
end
%
foo { |req| }
%
foo { |req1, req2| }
%
foo { |optl = foo| }
%
foo { |optl1 = foo, optl2 = bar| }
%
foo { |*| }
%
foo { |*rest| }
%
foo { |req,| }
%
foo { |*, post| }
%
foo { |*, post1, post2| }
%
foo { |key:| }
%
foo { |key1:, key2:| }
%
foo { |key: foo| }
%
foo { |key1: foo, key2: bar| }
%
foo { |**| }
%
foo { |**kwrest| }
%
foo { |&block| }
%
foo { |req1, req2, optl = foo, *rest, key1:, key2: bar, **kwrest, &block| }
%
foo do |foooooooooooooooooooooooooooooooooooooo, barrrrrrrrrrrrrrrrrrrrrrrrrrrrr|
end
