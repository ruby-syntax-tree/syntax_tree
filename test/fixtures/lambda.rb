%
-> {}
%
-> { foo }
%
->(foo, bar) { baz }
%
-> foo { bar }
-
->(foo) { bar }
%
-> () { foo }
-
-> { foo }
%
-> { fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
-> do
  fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
end
%
->(foo) { foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
->(foo) do
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
end
%
command foo, ->(bar) { bar }
%
command foo, ->(bar) { barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr }
-
command foo,
        ->(bar) { barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr }
%
command.call foo, ->(bar) { bar }
%
command.call foo, ->(bar) { barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr }
-
command.call foo,
             ->(bar) { barrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrrr }
%
-> { -> foo do bar end.baz }.qux
-
-> { ->(foo) { bar }.baz }.qux
%
->(;a) {}
-
->(; a) {}
%
->(; a) {}
%
->(; a,b) {}
-
->(; a, b) {}
%
->(; a, b) {}
%
->(;
a
) {}
-
->(; a) {}
%
->(; a , 
b
) {}
-
->(; a, b) {}
%
->(a = (b; c)) {}
%
-> do # comment1
  # comment2
end
% # multiline lambda in a command
command "arg" do
  -> {
    multi
    line
  }
end
-
command "arg" do
  -> do
    multi
    line
  end
end
% # multiline lambda in a command call
command.call "arg" do
  -> {
    multi
    line
  }
end
-
command.call "arg" do
  -> do
    multi
    line
  end
end
