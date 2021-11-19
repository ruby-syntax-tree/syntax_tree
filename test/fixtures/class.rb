%
class Foo
end
%
class Foo
  foo
end
%
class Foo
  # comment
end
%
class Foo # comment
end
%
module Foo
  class Bar
  end
end
%
class Foo < foo
end
%
class Foo < foo
  foo
end
%
class Foo < foo
  # comment
end
%
class Foo < foo # comment
end
%
module Foo
  class Bar < foo
  end
end
