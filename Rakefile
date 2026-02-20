# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"]
end

desc "Run conformance tests against Ruby/Native/JVM backends"
task :conformance do
  ruby "spec/conformance/runner.rb", *ARGV.drop_while { |a| a != "--" }.drop(1)
end

desc "Run conformance tests (native backend only)"
task "conformance:native" do
  ruby "spec/conformance/runner.rb", "--native-only"
end

desc "Run conformance tests (JVM backend only)"
task "conformance:jvm" do
  ruby "spec/conformance/runner.rb", "--jvm-only"
end

task default: :test
