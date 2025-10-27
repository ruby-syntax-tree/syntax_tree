# frozen_string_literal: true

require_relative "lib/syntax_tree/version"

Gem::Specification.new do |spec|
  spec.name = "syntax_tree"
  spec.version = SyntaxTree::VERSION
  spec.authors = ["Kevin Newton"]
  spec.email = ["kddnewton@gmail.com"]

  spec.summary = "A Ruby formatter"
  spec.homepage = "https://github.com/ruby-syntax-tree/syntax_tree"
  spec.license = "MIT"

  spec.metadata = {
    "rubygems_mfa_required" => "true",
    "allowed_push_host" => "https://rubygems.org",
    "source_code_uri" => spec.homepage,
    "changelog_uri" => "#{spec.homepage}/blob/main/CHANGELOG.md"
  }

  spec.files = %w[
    CHANGELOG.md
    CODE_OF_CONDUCT.md
    LICENSE
    README.md
    config/rubocop.yml
    doc/logo.svg
    exe/stree
    lib/prism/format.rb
    lib/syntax_tree.rb
    lib/syntax_tree/cli.rb
    lib/syntax_tree/lsp.rb
    lib/syntax_tree/rake.rb
    lib/syntax_tree/version.rb
    syntax_tree.gemspec
  ]

  spec.required_ruby_version = ">= 3.2.0"
  spec.bindir = "exe"
  spec.executables = spec.files.grep(%r{^exe/}) { |f| File.basename(f) }
  spec.require_paths = %w[lib]
  spec.add_dependency "prism"
end
