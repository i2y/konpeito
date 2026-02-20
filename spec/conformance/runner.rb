# frozen_string_literal: true

# Konpeito Conformance Test Runner
#
# Usage:
#   ruby spec/conformance/runner.rb [options] [pattern]
#
# Options:
#   --native-only   Run only native backend tests
#   --jvm-only      Run only JVM backend tests
#   --verbose       Show detailed output
#   --no-color      Disable colored output
#
# Examples:
#   ruby spec/conformance/runner.rb              # Run all specs on all backends
#   ruby spec/conformance/runner.rb --native-only # Run only native backend
#   ruby spec/conformance/runner.rb if            # Run only specs matching "if"

require "fileutils"
require_relative "lib/runner/discovery"
require_relative "lib/runner/executor"
require_relative "lib/runner/comparator"
require_relative "lib/runner/reporter"
require_relative "lib/runner/tag_manager"

module Conformance
  class Runner
    def initialize(args)
      @native = true
      @jvm = true
      @verbose = false
      @color = true
      @pattern = nil

      parse_args(args)
    end

    def run
      discovery = Discovery.new(pattern: @pattern)
      specs = discovery.find_specs

      if specs.empty?
        $stderr.puts "No spec files found#{@pattern ? " matching '#{@pattern}'" : ""}"
        return false
      end

      executor = Executor.new(verbose: @verbose)
      comparator = Comparator.new
      reporter = Reporter.new(verbose: @verbose, color: @color)
      tag_manager = TagManager.new

      puts "Running #{specs.size} conformance spec(s)..."
      puts ""

      specs.each do |spec_file|
        spec_name = File.basename(spec_file, ".rb")
        puts "#{spec_name}:"

        # Always run Ruby as reference
        ruby_result = executor.run_ruby(spec_file)
        ruby_parsed = comparator.parse_output(ruby_result.stdout)
        puts "  ruby: #{ruby_parsed.pass_count} passed, #{ruby_parsed.fail_count} failed"

        native_result = nil
        native_diffs = nil
        native_error = nil
        jvm_result_obj = nil
        jvm_diffs = nil
        jvm_error = nil

        # Native backend
        if @native
          native_result = executor.run_native(spec_file)
          if native_result.success
            native_parsed = comparator.parse_output(native_result.stdout)
            native_diffs = comparator.compare(ruby_result.stdout, native_result.stdout)
            status = native_diffs.empty? ? "MATCH" : "DIFF (#{native_diffs.size})"
            puts "  native: #{native_parsed.pass_count} passed, #{native_parsed.fail_count} failed [#{status}]"
          else
            native_error = native_result.error || "unknown error"
            puts "  native: ERROR - #{native_error}"
            if @verbose && !native_result.stderr.empty?
              native_result.stderr.lines.first(5).each { |l| puts "    #{l.chomp}" }
            end
          end
        end

        # JVM backend
        if @jvm
          jvm_result_obj = executor.run_jvm(spec_file)
          if jvm_result_obj.success
            jvm_parsed = comparator.parse_output(jvm_result_obj.stdout)
            jvm_diffs = comparator.compare(ruby_result.stdout, jvm_result_obj.stdout)
            status = jvm_diffs.empty? ? "MATCH" : "DIFF (#{jvm_diffs.size})"
            puts "  jvm: #{jvm_parsed.pass_count} passed, #{jvm_parsed.fail_count} failed [#{status}]"
          else
            jvm_error = jvm_result_obj.error || "unknown error"
            puts "  jvm: ERROR - #{jvm_error}"
            if @verbose && !jvm_result_obj.stderr.empty?
              jvm_result_obj.stderr.lines.first(5).each { |l| puts "    #{l.chomp}" }
            end
          end
        end

        reporter.add_result(
          spec_name: spec_name,
          ruby: ruby_parsed,
          native: @native ? (native_result&.success ? comparator.parse_output(native_result.stdout) : nil) : nil,
          jvm: @jvm ? (jvm_result_obj&.success ? comparator.parse_output(jvm_result_obj.stdout) : nil) : nil,
          native_diffs: native_diffs,
          jvm_diffs: jvm_diffs,
          native_error: native_error,
          jvm_error: jvm_error
        )
      end

      reporter.print_report
    end

    private

    def parse_args(args)
      args.each do |arg|
        case arg
        when "--native-only"
          @jvm = false
        when "--jvm-only"
          @native = false
        when "--verbose", "-v"
          @verbose = true
        when "--no-color"
          @color = false
        when /\A-/
          $stderr.puts "Unknown option: #{arg}"
          exit 1
        else
          @pattern = arg
        end
      end
    end
  end
end

exit(Conformance::Runner.new(ARGV).run ? 0 : 1)
