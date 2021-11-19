%
super()
%
super foo
%
super(foo)
%
super foo, bar
%
super(foo, bar)
%
super() # comment
%
super foo # comment
%
super(foo) # comment
%
super foo, bar # comment
%
super(foo, bar) # comment
%
super foo, # comment1
      bar # comment2
%
super(
  foo, # comment1
  bar # comment2
)
