%
foo = bar
%
foo =
  begin
    bar
  end
%
foo = <<~HERE
  bar
HERE
%
foo = barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
-
foo =
  barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr
%
foo = [barrrrrrrrrrrrrrrrrrrrr, barrrrrrrrrrrrrrrrrrrrr, barrrrrrrrrrrrrrrrrrrrr]
-
foo = [
  barrrrrrrrrrrrrrrrrrrrr,
  barrrrrrrrrrrrrrrrrrrrr,
  barrrrrrrrrrrrrrrrrrrrr
]
%
foo = { bar1: bazzzzzzzzzzzzzzz, bar2: bazzzzzzzzzzzzzzz, bar3: bazzzzzzzzzzzzzzz }
-
foo = {
  bar1: bazzzzzzzzzzzzzzz,
  bar2: bazzzzzzzzzzzzzzz,
  bar3: bazzzzzzzzzzzzzzz
}
