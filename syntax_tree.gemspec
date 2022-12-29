# frozen_string_literal: true

require_relative "lib/syntax_tree/version"

Gem::Specification.new do |spec|
  spec.name = "syntax_tree"
  spec.version = SyntaxTree::VERSION
  spec.authors = ["Kevin Newton"]
  spec.email = ["kddnewton@gmail.com"]

  spec.summary = "A parser based on ripper"
  spec.homepage = "https://github.com/kddnewton/syntax_tree"
  spec.license = "MIT"
  spec.metadata = { "rubygems_mfa_required" => "true" }

  spec.files =
    Dir.chdir(__dir__) do
      `git ls-files -z`.split("\x0")
        .reject { |f| f.match(%r{^(test|spec|features)/}) }
    end

  spec.required_ruby_version = ">= 2.7.0"

  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w[lib]

  spec.add_dependency "prettier_print", ">= 1.2.0"

  spec.add_development_dependency "bundler"
  spec.add_development_dependency "minitest"
  spec.add_development_dependency "rake"
  spec.add_development_dependency "rubocop"
  spec.add_development_dependency "simplecov"
end
