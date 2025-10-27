%
undef foo
%
undef foo, bar
%
undef foooooooooooooooooooooooooooooooooooooo, barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
-
undef foooooooooooooooooooooooooooooooooooooo,
      barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
%
undef foo # comment
%
undef foo, # comment
      bar
%
undef foo, # comment1
      bar, # comment2
      baz
%
undef foo,
      bar # comment
-
undef foo, bar # comment
%
undef :"foo", :"bar"
-
undef foo, bar
