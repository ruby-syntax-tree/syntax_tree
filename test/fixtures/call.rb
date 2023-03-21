%
foo.bar
%
foo.bar(baz)
%
foo.()
%
foo::()
-
foo.()
%
foo.(1)
%
foo::(1)
-
foo.(1)
%
foo.bar.baz.qux
%
fooooooooooooooooo.barrrrrrrrrrrrrrrrrrr {}.bazzzzzzzzzzzzzzzzzzzzzzzzzz.quxxxxxxxxx
-
fooooooooooooooooo
  .barrrrrrrrrrrrrrrrrrr {}
  .bazzzzzzzzzzzzzzzzzzzzzzzzzz
  .quxxxxxxxxx
%
foo. # comment
  bar
%
foo
  .bar
  .baz # comment
  .qux
  .quux
%
foo
  .bar
  .baz.
  # comment
  qux
  .quux
%
{ a: 1, b: 2 }.fooooooooooooooooo.barrrrrrrrrrrrrrrrrrr.bazzzzzzzzzzzz.quxxxxxxxxxxxx
-
{ a: 1, b: 2 }.fooooooooooooooooo
  .barrrrrrrrrrrrrrrrrrr
  .bazzzzzzzzzzzz
  .quxxxxxxxxxxxx
%
fooooooooooooooooo.barrrrrrrrrrrrrrrrrrr.bazzzzzzzzzzzz.quxxxxxxxxxxxx.each { block }
-
fooooooooooooooooo.barrrrrrrrrrrrrrrrrrr.bazzzzzzzzzzzz.quxxxxxxxxxxxx.each do
  block
end
%
foo.bar.baz.each do
  block1
  block2
end
%
a b do
end.c d
%
self.
=begin
=end
  to_s
%
fooooooooooooooooooooooooooooooooooo.barrrrrrrrrrrrrrrrrrrrrrrrrrrrrr.where.not(:id).order(:id)
-
fooooooooooooooooooooooooooooooooooo
  .barrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
  .where.not(:id)
  .order(:id)
