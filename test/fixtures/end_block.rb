%
END { foo }
%
END {
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
}
%
END {
  foo
}
-
END { foo }
%
END { foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
END {
  foooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
}
%
END { # comment
  foo
}
%
END {
  # comment
  foo
}
