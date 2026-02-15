# frozen_string_literal: true

require "json"
require "tmpdir"
require "fileutils"

module Konpeito
  module Codegen
    # JVM Backend: Orchestrates the compilation pipeline from HIR to .jar
    #
    # Pipeline:
    #   HIR → JVMGenerator → JSON IR → ASM tool (subprocess) → .class files → jar → .jar
    class JVMBackend
      ASM_TOOL_DIR = File.expand_path("../../../tools/konpeito-asm", __dir__)
      ASM_TOOL_JAR = File.join(ASM_TOOL_DIR, "konpeito-asm.jar")
      JAVA_HOME = ENV["JAVA_HOME"] || Platform.default_java_home

      attr_reader :output_file

      def initialize(jvm_generator, output_file:, module_name:, run_after: false, emit_ir: false, classpath: nil, library: false)
        @jvm_generator = jvm_generator
        @output_file = output_file
        @module_name = module_name
        @run_after = run_after
        @emit_ir = emit_ir
        @classpath = classpath
        @library = library
      end

      def generate
        ensure_asm_tool!

        Dir.mktmpdir("konpeito-jvm") do |tmpdir|
          classes_dir = File.join(tmpdir, "classes")
          FileUtils.mkdir_p(classes_dir)

          # Step 1: Generate JSON IR
          json_ir = @jvm_generator.to_json

          # Optionally save JSON IR for debugging
          if @emit_ir
            ir_path = @output_file.sub(/\.jar$/, ".json")
            FileUtils.mkdir_p(File.dirname(File.expand_path(ir_path)))
            File.write(ir_path, JSON.pretty_generate(@jvm_generator.to_json_ir))
            puts "JSON IR written to: #{ir_path}"
          end

          # Step 2: Run ASM tool to generate .class files
          run_asm_tool(json_ir, classes_dir)

          # Step 2.5: Copy runtime classes (KArray, KHash, etc.)
          copy_runtime_classes(classes_dir)

          if @library
            # Library mode: no Main-Class manifest
            create_jar_without_manifest(classes_dir)
          else
            # Step 3: Create manifest
            manifest_path = File.join(tmpdir, "MANIFEST.MF")
            main_class = @jvm_generator.send(:main_class_name).gsub("/", ".")
            File.write(manifest_path, "Main-Class: #{main_class}\n")

            # Step 4: Package into .jar
            create_jar(classes_dir, manifest_path)

            # Step 5: Optionally run
            run_jar if @run_after
          end
        end
      end

      private

      def ensure_asm_tool!
        unless File.exist?(ASM_TOOL_JAR)
          puts "Building ASM tool (first-time setup)..."
          build_script = File.join(ASM_TOOL_DIR, "build.sh")
          unless File.exist?(build_script)
            raise CodegenError, "ASM tool build script not found: #{build_script}"
          end

          output = `bash #{build_script} 2>&1`
          unless $?.success?
            $stderr.puts output
            raise CodegenError, "Failed to build ASM tool"
          end
          puts "ASM tool ready."
        end
      end

      def run_asm_tool(json_ir, output_dir)
        java_cmd = find_java

        # Run the ASM tool, passing JSON IR via stdin
        cmd = [java_cmd, "-jar", ASM_TOOL_JAR, output_dir]

        IO.popen(cmd, "r+", err: [:child, :out]) do |io|
          io.write(json_ir)
          io.close_write
          output = io.read
          unless output.strip.empty?
            # Check for errors
            if output.include?("Error") || output.include?("Exception")
              raise CodegenError, "ASM tool error:\n#{output}"
            end
          end
        end

        unless $?.success?
          raise CodegenError, "ASM tool failed with exit code #{$?.exitstatus}"
        end
      end

      def create_jar_without_manifest(classes_dir)
        jar_cmd = find_jar

        FileUtils.mkdir_p(File.dirname(File.expand_path(@output_file)))

        output_path = File.expand_path(@output_file)
        cmd = [jar_cmd, "cf", output_path, "-C", classes_dir, "."]

        result = system(*cmd)
        unless result
          raise CodegenError, "jar command failed"
        end
      end

      def create_jar(classes_dir, manifest_path)
        jar_cmd = find_jar

        # Ensure output directory exists
        FileUtils.mkdir_p(File.dirname(File.expand_path(@output_file)))

        # Create JAR with manifest
        output_path = File.expand_path(@output_file)
        cmd = [jar_cmd, "cfm", output_path, manifest_path, "-C", classes_dir, "."]

        result = system(*cmd)
        unless result
          raise CodegenError, "jar command failed"
        end
      end

      def run_jar
        java_cmd = find_java
        if @classpath
          # Use -cp mode so external JARs are on the classpath
          cp = "#{File.expand_path(@output_file)}#{Platform.classpath_separator}#{@classpath}"
          main_class = @jvm_generator.send(:main_class_name).gsub("/", ".")
          cmd = [java_cmd]
          cmd << "-XstartOnFirstThread" if RUBY_PLATFORM.include?("darwin")
          cmd += ["-cp", cp, main_class]
          puts "Running: #{cmd.join(' ')}"
          system(*cmd)
        else
          puts "Running: java -jar #{@output_file}"
          system(java_cmd, "-jar", @output_file)
        end
      end

      def find_java
        # Try JAVA_HOME first, then PATH
        java_path = File.join(JAVA_HOME, "bin", "java")
        return java_path if File.exist?(java_path)

        # Try PATH
        java_in_path = Platform.find_executable("java")
        return java_in_path if java_in_path

        raise CodegenError, "Java not found. Install Java 21+: #{Platform.java_install_hint}"
      end

      def copy_runtime_classes(classes_dir)
        runtime_dir = File.join(ASM_TOOL_DIR, "runtime-classes")
        return unless File.directory?(runtime_dir)

        # Copy runtime .class files preserving directory structure
        Dir.glob(File.join(runtime_dir, "**", "*.class")).each do |class_file|
          relative_path = class_file.sub("#{runtime_dir}/", "")
          dest = File.join(classes_dir, relative_path)
          FileUtils.mkdir_p(File.dirname(dest))
          FileUtils.cp(class_file, dest)
        end
      end

      def find_jar
        jar_path = File.join(JAVA_HOME, "bin", "jar")
        return jar_path if File.exist?(jar_path)

        jar_in_path = Platform.find_executable("jar")
        return jar_in_path if jar_in_path

        raise CodegenError, "jar command not found. Install Java 21+: #{Platform.java_install_hint}"
      end
    end
  end
end
