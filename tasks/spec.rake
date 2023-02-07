# frozen_string_literal: true

desc "Run mspec tests using YARV emulation"
task :spec do
  specs = File.expand_path("../spec/ruby/language/**/*_spec.rb", __dir__)

  Dir[specs].each do |filepath|
    sh "exe/yarv ./spec/mspec/bin/mspec-tag #{filepath}"
  end
end
