%
def foo = bar
%
def foo(bar) = baz
%
def foo() = bar
% # >= 3.1.0
def foo = bar baz
% # >= 3.1.0
def self.foo = bar
% # >= 3.1.0
def self.foo(bar) = baz
% # >= 3.1.0
def self.foo() = bar
% # >= 3.1.0
def self.foo = bar baz
%
begin
  true
rescue StandardError
  false
end

def foo? = true
