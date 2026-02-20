# frozen_string_literal: true

module Conformance
  class Reporter
    def initialize(verbose: false, color: true)
      @verbose = verbose
      @color = color
      @results = []
    end

    def add_result(spec_name:, ruby:, native: nil, jvm: nil, native_diffs: nil, jvm_diffs: nil, native_error: nil, jvm_error: nil)
      @results << {
        spec_name: spec_name,
        ruby: ruby,
        native: native,
        jvm: jvm,
        native_diffs: native_diffs || [],
        jvm_diffs: jvm_diffs || [],
        native_error: native_error,
        jvm_error: jvm_error
      }
    end

    def print_report
      puts ""
      puts "=" * 60
      puts "Konpeito Conformance Test Results"
      puts "=" * 60
      puts ""

      total_specs = @results.size
      native_pass = 0
      native_fail = 0
      native_error = 0
      jvm_pass = 0
      jvm_fail = 0
      jvm_error = 0

      @results.each do |r|
        print_spec_result(r)

        if r[:native_error]
          native_error += 1
        elsif r[:native_diffs].empty? && r[:native]
          native_pass += 1
        elsif r[:native]
          native_fail += 1
        end

        if r[:jvm_error]
          jvm_error += 1
        elsif r[:jvm_diffs].empty? && r[:jvm]
          jvm_pass += 1
        elsif r[:jvm]
          jvm_fail += 1
        end
      end

      puts ""
      puts "-" * 60
      puts "Summary: #{total_specs} spec files"
      puts ""

      if native_pass + native_fail + native_error > 0
        puts "  Native: #{colorize(native_pass.to_s, :green)} pass, #{colorize(native_fail.to_s, native_fail > 0 ? :red : :green)} diff, #{colorize(native_error.to_s, native_error > 0 ? :red : :green)} error"
      end

      if jvm_pass + jvm_fail + jvm_error > 0
        puts "  JVM:    #{colorize(jvm_pass.to_s, :green)} pass, #{colorize(jvm_fail.to_s, jvm_fail > 0 ? :red : :green)} diff, #{colorize(jvm_error.to_s, jvm_error > 0 ? :red : :green)} error"
      end

      puts ""

      all_pass = native_fail == 0 && native_error == 0 && jvm_fail == 0 && jvm_error == 0
      all_pass
    end

    private

    def print_spec_result(r)
      name = r[:spec_name]

      # Native
      if r[:native]
        if r[:native_error]
          status = colorize("ERROR", :red)
          puts "  #{name}: native=#{status} (#{r[:native_error]})"
        elsif r[:native_diffs].empty?
          status = colorize("MATCH", :green)
          puts "  #{name}: native=#{status}"
        else
          status = colorize("DIFF", :red)
          puts "  #{name}: native=#{status} (#{r[:native_diffs].size} differences)"
          if @verbose
            r[:native_diffs].each do |d|
              puts "    expected: #{d[:expected]}"
              puts "    actual:   #{d[:actual]}"
            end
          end
        end
      end

      # JVM
      if r[:jvm]
        if r[:jvm_error]
          status = colorize("ERROR", :red)
          puts "  #{name}: jvm=#{status} (#{r[:jvm_error]})"
        elsif r[:jvm_diffs].empty?
          status = colorize("MATCH", :green)
          puts "  #{name}: jvm=#{status}"
        else
          status = colorize("DIFF", :red)
          puts "  #{name}: jvm=#{status} (#{r[:jvm_diffs].size} differences)"
          if @verbose
            r[:jvm_diffs].each do |d|
              puts "    expected: #{d[:expected]}"
              puts "    actual:   #{d[:actual]}"
            end
          end
        end
      end
    end

    def colorize(text, color)
      return text unless @color
      case color
      when :green then "\e[32m#{text}\e[0m"
      when :red then "\e[31m#{text}\e[0m"
      when :yellow then "\e[33m#{text}\e[0m"
      else text
      end
    end
  end
end
