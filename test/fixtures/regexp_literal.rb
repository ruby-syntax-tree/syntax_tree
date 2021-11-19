%
/foo/
%
%r{foo}
-
/foo/
%
%r/foo/
-
/foo/
%
%r[foo]
-
/foo/
%
%r(foo)
-
/foo/
%
%r{foo/bar/baz}
%
/foo #{bar} baz/
%
/foo/i
%
%r{foo/bar/baz}mi
%
/#$&/
-
/#{$&}/
%
%r(a{b/c})
%
%r[a}b/c]
%
%r(a}bc)
-
/a}bc/
%
/\\A
  [[:digit:]]+ # 1 or more digits before the decimal point
  (\\.         # Decimal point
  [[:digit:]]+ # 1 or more digits after the decimal point
  )? # The decimal point and following digits are optional
\\Z/x
%
foo %r{ bar}
%
foo %r{= bar}
%
foo(/ bar/)
