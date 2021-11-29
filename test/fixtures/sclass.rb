%
class << self
  foo
end
%
class << foo
  bar
end
%
class << self # comment
  foo
end
%
class << self
  # comment
end
%
class << self
  # comment1
  # comment2
end
