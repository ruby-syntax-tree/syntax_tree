%
tap { next }
%
tap { next foo }
%
tap { next foo, bar }
%
tap { next(foo) }
%
tap { next fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo }
-
tap do
  next(
    fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  )
end
%
tap { next(fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo) }
-
tap do
  next(
    fooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooooo
  )
end
%
tap { next (foo), bar }
%
tap do
  next(
    foo
    bar
  )
end
%
tap { next(1) }
-
tap { next 1 }
%
tap { next(1.0) }
-
tap { next 1.0 }
%
tap { next($a) }
-
tap { next $a }
%
tap { next(@@a) }
-
tap { next @@a }
%
tap { next(self) }
-
tap { next self }
%
tap { next(@a) }
-
tap { next @a }
%
tap { next(A) }
-
tap { next A }
%
tap { next([]) }
-
tap { next [] }
%
tap { next([1]) }
-
tap { next [1] }
%
tap { next([1, 2]) }
-
tap { next 1, 2 }
%
tap { next fun foo do end }
-
tap do
  next(
    fun foo do
    end
  )
end
