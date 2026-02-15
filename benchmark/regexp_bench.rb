# frozen_string_literal: true

# Benchmark: Regular Expression Performance
# Usage: bundle exec ruby benchmark/regexp_bench.rb
#
# This benchmark tests the regexp literal feature.
# Compares native compiled /pattern/ vs pure Ruby.

require "benchmark/ips"
require "tempfile"
require "fileutils"

# Add lib to load path
$LOAD_PATH.unshift File.expand_path("../lib", __dir__)
require "konpeito"

# Source with regexp literals
REGEXP_SOURCE = <<~RUBY
  def match_email(str)
    str =~ /\\w+@\\w+\\.\\w+/
  end

  def match_digits(str)
    str =~ /\\d+/
  end

  def match_case_insensitive(str)
    str =~ /hello/i
  end
RUBY

REGEXP_RBS = <<~RBS
  module TopLevel
    def match_email: (String str) -> Integer?
    def match_digits: (String str) -> Integer?
    def match_case_insensitive: (String str) -> Integer?
  end
RBS

def compile_native
  tmp_dir = File.expand_path("../tmp", __dir__)
  FileUtils.mkdir_p(tmp_dir)

  timestamp = Time.now.to_i
  source_path = File.join(tmp_dir, "regexp_bench_#{timestamp}.rb")
  rbs_path = File.join(tmp_dir, "regexp_bench_#{timestamp}.rbs")
  output_path = File.join(tmp_dir, "regexp_bench_#{timestamp}.bundle")

  File.write(source_path, REGEXP_SOURCE)
  File.write(rbs_path, REGEXP_RBS)

  Konpeito::Compiler.new(
    source_file: source_path,
    output_file: output_path,
    format: :cruby_ext,
    rbs_paths: [rbs_path],
    optimize: true
  ).compile

  output_path
ensure
  File.unlink(source_path) rescue nil
  File.unlink(rbs_path) rescue nil
end

# Pure Ruby implementations
module PureRuby
  def self.match_email(str)
    str =~ /\w+@\w+\.\w+/
  end

  def self.match_digits(str)
    str =~ /\d+/
  end

  def self.match_case_insensitive(str)
    str =~ /hello/i
  end
end

puts "Compiling native extension with regexp literals..."
bundle_path = compile_native
require bundle_path

$native_obj = Object.new

module Native
  class << self
    define_method(:match_email) { |str| $native_obj.send(:match_email, str) }
    define_method(:match_digits) { |str| $native_obj.send(:match_digits, str) }
    define_method(:match_case_insensitive) { |str| $native_obj.send(:match_case_insensitive, str) }
  end
end

puts "Compiled: #{bundle_path}"
puts

# Test strings
email_str = "Contact us at test@example.com for more info"
digit_str = "There are 42 items in stock"
hello_str = "HELLO World"

# Verify correctness
puts "Verifying correctness..."
raise "email match mismatch" unless PureRuby.match_email(email_str) == Native.match_email(email_str)
raise "digit match mismatch" unless PureRuby.match_digits(digit_str) == Native.match_digits(digit_str)
raise "case insensitive mismatch" unless PureRuby.match_case_insensitive(hello_str) == Native.match_case_insensitive(hello_str)
puts "All results match!"
puts
puts "match_email(\"#{email_str}\") = #{Native.match_email(email_str)}"
puts "match_digits(\"#{digit_str}\") = #{Native.match_digits(digit_str)}"
puts "match_case_insensitive(\"#{hello_str}\") = #{Native.match_case_insensitive(hello_str)}"
puts

puts "=" * 60
puts "Benchmark: Email Pattern Match"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.match_email(email_str) }
  x.report("Native") { Native.match_email(email_str) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Digit Pattern Match"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.match_digits(digit_str) }
  x.report("Native") { Native.match_digits(digit_str) }
  x.compare!
end

puts
puts "=" * 60
puts "Benchmark: Simple Pattern Match (case insensitive)"
puts "=" * 60
Benchmark.ips do |x|
  x.report("Pure Ruby") { PureRuby.match_case_insensitive(hello_str) }
  x.report("Native") { Native.match_case_insensitive(hello_str) }
  x.compare!
end

puts
puts "-" * 60
puts "Note: Regexp matching uses rb_reg_match internally."
puts "Performance is dominated by regex engine, not compilation."
puts "-" * 60

# Cleanup
File.unlink(bundle_path) rescue nil
