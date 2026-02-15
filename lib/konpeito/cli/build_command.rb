# frozen_string_literal: true

module Konpeito
  module Commands
    # Build command - compiles Ruby source to native code
    class BuildCommand < BaseCommand
      def self.command_name
        "build"
      end

      def self.description
        "Compile Ruby source to native code (CRuby extension)"
      end

      def run
        parse_options!

        if args.empty?
          error("No source file specified. Usage: konpeito build <source.rb>")
        end

        source_file = args.first

        unless File.exist?(source_file)
          error("File not found: #{source_file}")
        end

        compile(source_file)
      end

      protected

      def default_options
        {
          output: config.build_output,
          format: config.build_format,
          verbose: false,
          rbs_paths: config.rbs_paths.dup,
          require_paths: config.require_paths.dup,
          color: $stderr.tty?,
          debug: config.debug?,
          profile: config.profile?,
          incremental: config.incremental?,
          clean_cache: false,
          inline_rbs: false,
          target: :native,
          run_after: false,
          emit_ir: false,
          classpath: nil,
          library: false,
          stats: false,
          quiet: false
        }
      end

      def setup_option_parser(opts)
        opts.on("-o", "--output FILE", "Output file name") do |file|
          options[:output] = file
        end

        opts.on("-f", "--format FORMAT", %i[cruby_ext standalone],
                "Output format (cruby_ext, standalone)") do |format|
          options[:format] = format
        end

        opts.on("-g", "--debug", "Generate debug info (DWARF) for lldb/gdb") do
          options[:debug] = true
        end

        opts.on("-p", "--profile", "Enable profiling (function call counts and timing)") do
          options[:profile] = true
        end

        opts.on("-I", "--require-path PATH", "Add require search path (can be used multiple times)") do |path|
          options[:require_paths] << path
        end

        opts.on("--rbs FILE", "RBS type definition file (can be used multiple times)") do |file|
          options[:rbs_paths] << file
        end

        opts.on("--incremental", "Enable incremental compilation (cache unchanged files)") do
          options[:incremental] = true
        end

        opts.on("--clean-cache", "Clear compilation cache before building") do
          options[:clean_cache] = true
        end

        opts.on("--inline", "Use inline RBS annotations (# @rbs, #:) from Ruby source") do
          options[:inline_rbs] = true
        end

        opts.on("--target TARGET", %i[native jvm], "Target platform (native, jvm)") do |target|
          options[:target] = target
        end

        opts.on("--run", "Run the compiled program after building") do
          options[:run_after] = true
        end

        opts.on("--emit-ir", "Emit intermediate representation for debugging") do
          options[:emit_ir] = true
        end

        opts.on("--classpath PATH", "Add external JARs/directories to classpath (colon-separated)") do |path|
          options[:classpath] = path
        end

        opts.on("--lib", "Build as library JAR (no Main-Class, JVM target only)") do
          options[:library] = true
        end

        opts.on("--stats", "Show optimization statistics") do
          options[:stats] = true
        end

        opts.on("-q", "--quiet", "Suppress non-error output") do
          options[:quiet] = true
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito build [options] <source.rb>

          Examples:
            konpeito build src/main.rb                 Compile to CRuby extension
            konpeito build --target jvm src/main.rb    Compile to JAR
            konpeito build --stats src/main.rb         Show optimization stats
            konpeito build -g src/main.rb              With debug info (DWARF)
            konpeito build --run src/main.rb           Build and run immediately
        BANNER
      end

      private

      def compile(source_file)
        output_file = options[:output] || default_output_name(source_file, format: options[:format],
                                                                          target: options[:target])

        # Auto-add lib/*.jar to classpath for JVM target
        classpath = options[:classpath]
        if options[:target] == :jvm
          lib_jars = Dir.glob("lib/*.jar")
          unless lib_jars.empty?
            lib_cp = lib_jars.join(Platform.classpath_separator)
            classpath = classpath ? "#{classpath}#{Platform.classpath_separator}#{lib_cp}" : lib_cp
          end
        end

        target_label = options[:target] == :jvm ? "jvm" : "native"
        emit("Compiling", "#{source_file} (#{target_label})") unless options[:quiet]

        compiler = Compiler.new(
          source_file: source_file,
          output_file: output_file,
          format: options[:format],
          verbose: options[:verbose],
          rbs_paths: options[:rbs_paths],
          require_paths: options[:require_paths],
          debug: options[:debug],
          profile: options[:profile],
          incremental: options[:incremental],
          clean_cache: options[:clean_cache],
          inline_rbs: options[:inline_rbs],
          target: options[:target],
          run_after: options[:run_after],
          emit_ir: options[:emit_ir],
          classpath: classpath,
          library: options[:library]
        )

        compiler.compile
        display_diagnostics(compiler.diagnostics)

        if compiler.diagnostics.any?(&:error?)
          error_count = compiler.diagnostics.count(&:error?)
          emit_error("Failed", "with #{error_count} error(s)") unless options[:quiet]
          exit 1
        end

        unless options[:quiet]
          stats = compiler.compile_stats

          # Show optimization stats if --stats
          if options[:stats] && stats
            resolved_msg = "#{stats.resolved_files} file(s)"
            resolved_msg += ", #{stats.rbs_count} RBS definition(s)" if stats.rbs_count > 0
            emit("Resolved", resolved_msg)

            opt_parts = []
            opt_parts << "#{stats.specializations} specialization(s)" if stats.specializations > 0
            opt_parts << "#{stats.inlined} inlined" if stats.inlined > 0
            opt_parts << "#{stats.hoisted} hoisted" if stats.hoisted > 0
            emit("Optimized", opt_parts.join(", ")) unless opt_parts.empty?
          end

          # Show finished line with timing and size
          if stats
            duration_str = "%.2fs" % stats.duration_s
            size_str = File.exist?(output_file) ? " (#{format_size(File.size(output_file))})" : ""
            emit("Finished", "in #{duration_str} -> #{output_file}#{size_str}")
          end
        end
      rescue Konpeito::DependencyError => e
        display_dependency_error(e)
        exit 1
      rescue Konpeito::ParseError => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      rescue Konpeito::Error => e
        $stderr.puts "Error: #{e.message}"
        exit 1
      end
    end
  end
end
