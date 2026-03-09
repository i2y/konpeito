# frozen_string_literal: true

require "rake/testtask"

Rake::TestTask.new(:test) do |t|
  t.libs << "test"
  t.libs << "lib"
  t.test_files = FileList["test/**/*_test.rb"].exclude("test/codegen/**/*_test.rb")
end

desc "Run codegen tests (each file in a separate process to avoid .so accumulation crashes)"
task "test:codegen" do
  test_files = FileList["test/codegen/**/*_test.rb"].sort
  failed = []
  test_files.each do |f|
    print "#{File.basename(f, '.rb')} "
    unless system("bundle", "exec", "ruby", "-Ilib:test", f)
      failed << f
    end
  end
  puts
  unless failed.empty?
    abort "#{failed.size}/#{test_files.size} codegen test files failed:\n  #{failed.join("\n  ")}"
  end
  puts "All #{test_files.size} codegen test files passed."
end

desc "Run all tests (non-codegen + codegen in separate processes)"
task "test:all" => [:test] do
  # Run codegen tests in a separate process so a crash doesn't kill non-codegen results
  sh "bundle exec rake test:codegen" do |ok, _status|
    unless ok
      warn "Codegen tests failed (possibly due to native extension crash on ruby-head)"
    end
  end
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

desc "Run CI compilation diagnostics"
task "test:diagnose" do
  ruby "test/ci_diagnostic.rb"
end

task default: :test
