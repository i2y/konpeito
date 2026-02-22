# frozen_string_literal: true

require "open3"
require "tmpdir"
require "rbconfig"

module Conformance
  class Executor
    COMPILE_TIMEOUT = 30
    RUN_TIMEOUT = 10

    KONPEITO_ROOT = File.expand_path("../../../..", __dir__)
    KONPEITO_BIN = File.join(KONPEITO_ROOT, "bin", "konpeito")

    Result = Struct.new(:stdout, :stderr, :success, :error, keyword_init: true)

    def initialize(verbose: false)
      @verbose = verbose
      @dlext = RbConfig::CONFIG["DLEXT"] || "bundle"
      @java = find_java
    end

    def run_ruby(spec_file)
      run_command(["ruby", spec_file], timeout: RUN_TIMEOUT, label: "ruby")
    end

    def run_native(spec_file)
      Dir.mktmpdir("konpeito_conformance") do |tmpdir|
        base = File.basename(spec_file, ".rb")
        bundle_file = File.join(tmpdir, "#{base}.#{@dlext}")

        # Compile
        compile_result = run_command(
          ["ruby", "-I#{KONPEITO_ROOT}/lib", KONPEITO_BIN, "build", "-o", bundle_file, spec_file],
          timeout: COMPILE_TIMEOUT,
          label: "native compile"
        )

        unless compile_result.success
          return Result.new(
            stdout: "",
            stderr: compile_result.stderr,
            success: false,
            error: "native compilation failed"
          )
        end

        # Run
        run_command(
          ["ruby", "-r", bundle_file, "-e", "run_tests"],
          timeout: RUN_TIMEOUT,
          label: "native run"
        )
      end
    end

    def run_jvm(spec_file)
      Dir.mktmpdir("konpeito_conformance") do |tmpdir|
        base = File.basename(spec_file, ".rb")
        jar_file = File.join(tmpdir, "#{base}.jar")

        # Compile
        compile_result = run_command(
          ["ruby", "-I#{KONPEITO_ROOT}/lib", KONPEITO_BIN, "build", "--target", "jvm", "-o", jar_file, spec_file],
          timeout: COMPILE_TIMEOUT,
          label: "jvm compile"
        )

        unless compile_result.success
          return Result.new(
            stdout: "",
            stderr: compile_result.stderr,
            success: false,
            error: "JVM compilation failed"
          )
        end

        # Run
        run_command(
          [@java, "-jar", jar_file],
          timeout: RUN_TIMEOUT,
          label: "jvm run"
        )
      end
    end

    private

    def run_command(cmd, timeout:, label:)
      log("  Running [#{label}]: #{cmd.join(' ')}")

      stdout = +""
      stderr = +""
      status = nil

      Open3.popen3(*cmd, chdir: KONPEITO_ROOT) do |stdin, out, err, wait_thr|
        stdin.close
        deadline = Process.clock_gettime(Process::CLOCK_MONOTONIC) + timeout

        out_thread = Thread.new { out.read }
        err_thread = Thread.new { err.read }

        remaining = deadline - Process.clock_gettime(Process::CLOCK_MONOTONIC)
        if remaining > 0 && wait_thr.join(remaining)
          status = wait_thr.value
          stdout = out_thread.value || ""
          stderr = err_thread.value || ""
        else
          # Timeout — kill the process
          Process.kill("KILL", wait_thr.pid) rescue nil
          wait_thr.join(2) rescue nil
          out_thread.kill rescue nil
          err_thread.kill rescue nil
          return Result.new(
            stdout: "",
            stderr: "timeout after #{timeout}s",
            success: false,
            error: "timeout after #{timeout}s"
          )
        end
      end

      log("  [#{label}] exit=#{status&.exitstatus}") if @verbose
      log("  [#{label}] stderr: #{stderr.strip}") if @verbose && !stderr.strip.empty?

      Result.new(
        stdout: stdout,
        stderr: stderr,
        success: status&.success? || false,
        error: status&.success? ? nil : "exit code #{status&.exitstatus}"
      )
    rescue Errno::ENOENT => e
      Result.new(stdout: "", stderr: e.message, success: false, error: e.message)
    end

    def find_java
      # Check PATH first
      java_in_path = Open3.capture3("which", "java").first.strip
      if !java_in_path.empty?
        # Verify it actually works (macOS stub may fail)
        _, _, status = Open3.capture3(java_in_path, "-version")
        return java_in_path if status.success?
      end

      # Homebrew openjdk locations
      %w[openjdk@21 openjdk@22 openjdk@23 openjdk].each do |pkg|
        candidate = "/opt/homebrew/opt/#{pkg}/bin/java"
        if File.executable?(candidate)
          _, _, status = Open3.capture3(candidate, "-version")
          return candidate if status.success?
        end
      end

      # Fallback
      "java"
    end

    def log(msg)
      $stderr.puts(msg) if @verbose
    end
  end
end
