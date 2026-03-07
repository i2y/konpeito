# frozen_string_literal: true

module Konpeito
  module Commands
    # Run command - build and execute in one step
    class RunCommand < BaseCommand
      def self.command_name
        "run"
      end

      def self.description
        "Build and run a Konpeito program"
      end

      def run
        parse_options!

        source_file = args.first
        unless source_file
          # Try to find default source from config or convention
          source_file = find_default_source
          unless source_file
            error("No source file specified. Usage: konpeito run [options] <source.rb>")
          end
        end

        unless File.exist?(source_file)
          error("File not found: #{source_file}")
        end

        target = options[:target] || config.target

        case target
        when :jvm
          run_jvm(source_file)
        else
          run_native(source_file)
        end
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          target: nil,
          classpath: nil,
          rbs_paths: config.rbs_paths.dup,
          require_paths: config.require_paths.dup,
          inline_rbs: false,
          lib: false,
          no_cache: false,
          clean_run_cache: false
        }
      end

      def setup_option_parser(opts)
        opts.on("--target TARGET", %i[native jvm], "Target platform (native, jvm)") do |target|
          options[:target] = target
        end

        opts.on("--classpath PATH", "Add external JARs/directories to classpath (colon-separated)") do |path|
          options[:classpath] = path
        end

        opts.on("--rbs FILE", "RBS type definition file (can be used multiple times)") do |file|
          options[:rbs_paths] << file
        end

        opts.on("-I", "--require-path PATH", "Add require search path") do |path|
          options[:require_paths] << path
        end

        opts.on("--inline", "Use inline RBS annotations (# @rbs, #:) from Ruby source") do
          options[:inline_rbs] = true
        end

        opts.on("--no-cache", "Force recompilation (skip run cache)") do
          options[:no_cache] = true
        end

        opts.on("--clean-run-cache", "Clear the run cache before building") do
          options[:clean_run_cache] = true
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito run [options] [source.rb]

          Examples:
            konpeito run src/main.rb                   Build and run (native, cached)
            konpeito run --no-cache src/main.rb        Force recompilation
            konpeito run --clean-run-cache src/main.rb Clear cache, then build and run
            konpeito run --inline src/main.rb          Build and run with inline RBS
            konpeito run --target jvm src/main.rb      Build and run (JVM)
        BANNER
      end

      private

      def find_default_source
        # Check common source locations
        candidates = ["src/main.rb", "main.rb", "app.rb"]
        candidates.find { |f| File.exist?(f) }
      end

      def run_jvm(source_file)
        # Build classpath from config + options + lib/*.jar
        classpath = build_classpath

        # Build args for build command
        build_args = build_jvm_args(source_file, classpath)
        build_args << "--run"

        Commands::BuildCommand.new(build_args, config: config).run
      end

      def run_native(source_file)
        require "konpeito/cache"

        basename = "#{File.basename(source_file, '.rb')}#{Platform.shared_lib_extension}"
        run_cache = Cache::RunCache.new

        if options[:clean_run_cache]
          run_cache.clean!
          emit("Cleaned", "run cache")
        end

        if options[:no_cache]
          build_and_run_tmpdir(source_file, basename)
          return
        end

        # Compute cache key once (runs DependencyResolver)
        cache_key = compute_run_cache_key(source_file, run_cache)

        # Try cache hit
        if cache_key
          artifact = run_cache.lookup(cache_key, basename)
          if artifact
            emit("Cached", source_file)
            emit("Running", artifact)
            run_without_bundler("ruby", "-r", artifact, "-e", "")
            return
          end
        end

        # Cache miss: build into cache dir
        if cache_key
          build_and_run_cached(source_file, run_cache, cache_key, basename)
        else
          build_and_run_tmpdir(source_file, basename)
        end
      end

      def compute_run_cache_key(source_file, run_cache)
        resolver = DependencyResolver.new(
          base_paths: options[:require_paths],
          verbose: false
        )
        resolver.resolve(source_file)

        all_sources = resolver.resolved_files.keys
        auto_rbs = resolver.rbs_paths
        all_rbs = (options[:rbs_paths].map { |p| File.expand_path(p) } + auto_rbs).uniq
        all_rbs = all_rbs.select { |f| File.exist?(f) }

        options_hash = {
          "inline_rbs" => options[:inline_rbs].to_s,
          "target" => "native"
        }

        run_cache.compute_cache_key(
          source_files: all_sources,
          rbs_files: all_rbs,
          options_hash: options_hash
        )
      rescue StandardError => e
        puts_verbose("Cache key computation failed: #{e.message}")
        nil
      end

      def build_and_run_cached(source_file, run_cache, cache_key, basename)
        dir = run_cache.artifact_dir(cache_key)
        FileUtils.mkdir_p(dir)
        output_file = File.join(dir, basename)

        build_args = build_native_args(source_file, output_file)
        Commands::BuildCommand.new(build_args, config: config).run

        run_cache.store(cache_key, basename)

        emit("Running", output_file)
        run_without_bundler("ruby", "-r", output_file, "-e", "")
      end

      def build_and_run_tmpdir(source_file, basename)
        require "tmpdir"

        @run_tmpdir = File.join(Dir.tmpdir, "konpeito_run_#{Process.pid}")
        FileUtils.mkdir_p(@run_tmpdir)
        output_file = File.join(@run_tmpdir, basename)

        build_args = build_native_args(source_file, output_file)
        Commands::BuildCommand.new(build_args, config: config).run

        emit("Running", output_file)
        run_without_bundler("ruby", "-r", output_file, "-e", "")
      ensure
        FileUtils.rm_rf(@run_tmpdir) if @run_tmpdir && Dir.exist?(@run_tmpdir)
      end

      def build_native_args(source_file, output_file)
        build_args = ["-o", output_file]
        build_args << "-v" if options[:verbose]
        build_args << "--no-color" unless options[:color]
        build_args << "--inline" if options[:inline_rbs]
        options[:rbs_paths].each { |p| build_args << "--rbs" << p }
        options[:require_paths].each { |p| build_args << "-I" << p }
        build_args << source_file
        build_args
      end

      def build_classpath
        parts = []

        # From config
        cp = options[:classpath] || config.jvm_classpath
        parts << cp unless cp.empty?

        # From lib/*.jar (downloaded dependencies)
        lib_jars = Dir.glob("lib/*.jar")
        parts << lib_jars.join(Platform.classpath_separator) unless lib_jars.empty?

        parts.reject(&:empty?).join(Platform.classpath_separator)
      end

      # Run a command without Bundler's environment restrictions.
      # When konpeito is invoked via `bundle exec`, child processes inherit
      # BUNDLE_GEMFILE/RUBYOPT which restrict gem access. The compiled extension
      # may require gems not in the current Gemfile.
      def run_without_bundler(*cmd)
        if defined?(Bundler) && Bundler.respond_to?(:with_unbundled_env)
          Bundler.with_unbundled_env { system(*cmd) }
        else
          system(*cmd)
        end
      end

      def build_jvm_args(source_file, classpath)
        build_args = ["--target", "jvm"]
        build_args << "-v" if options[:verbose]
        build_args << "--no-color" unless options[:color]
        build_args << "--inline" if options[:inline_rbs]
        build_args += ["--classpath", classpath] unless classpath.empty?
        options[:rbs_paths].each { |p| build_args << "--rbs" << p }
        options[:require_paths].each { |p| build_args << "-I" << p }
        build_args << source_file
        build_args
      end
    end
  end
end
