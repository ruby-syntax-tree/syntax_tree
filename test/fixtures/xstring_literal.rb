%
`foo`
%
`foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo`
%
`foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo`.to_s
%
%x[foo]
-
`foo`
%
%x[foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo]
-
`foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo`
%
%x[foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo].to_s
-
`foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo`.to_s
%
`foo` # comment
