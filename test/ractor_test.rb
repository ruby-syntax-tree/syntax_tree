# frozen_string_literal: true

# Don't run this test if we're in a version of Ruby that doesn't have Ractors.
return unless defined?(Ractor)

# Don't run this version on Ruby 3.0.0. For some reason it just hangs within the
# main Ractor waiting for this children. Not going to investigate it since it's
# already been fixed in 3.1.0.
return if Gem::Version.new(RUBY_VERSION) < Gem::Version.new("3.1.0")

require_relative "test_helper"

module SyntaxTree
  class RactorTest < Minitest::Test
    def test_formatting
      ractors =
        filepaths.map do |filepath|
          # At the moment we have to parse in the main Ractor because Ripper is
          # not marked as a Ractor-safe extension.
          source = SyntaxTree.read(filepath)
          program = SyntaxTree.parse(source)

          Ractor.new(source, program, name: filepath) do |source, program|
            SyntaxTree::Formatter.format(source, program)
          end
        end

      ractors.each(&:take)
    end

    private

    def filepaths
      Dir.glob(File.expand_path("../lib/syntax_tree/{node,parser}.rb", __dir__))
    end
  end
end
