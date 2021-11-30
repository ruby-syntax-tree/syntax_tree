%
class Foo
  private
end
%
class Foo
  private
  def foo
  end
end
-
class Foo
  private

  def foo
  end
end
%
class Foo
  def foo
  end
  private
end
-
class Foo
  def foo
  end

  private
end
