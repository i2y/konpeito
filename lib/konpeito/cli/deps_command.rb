# frozen_string_literal: true

require "net/http"
require "fileutils"

module Konpeito
  module Commands
    # Deps command - analyze source file dependencies or download Maven JARs
    class DepsCommand < BaseCommand
      MAVEN_CENTRAL_BASE = "https://repo1.maven.org/maven2"

      def self.command_name
        "deps"
      end

      def self.description
        "Analyze source file dependencies"
      end

      def run
        parse_options!

        if options[:fetch]
          fetch_jars
          return
        end

        if args.empty?
          source_file = find_default_source
          unless source_file
            puts option_parser_help
            return
          end
        else
          source_file = args.first
        end

        unless File.exist?(source_file)
          error("File not found: #{source_file}")
        end

        analyze(source_file)
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          fetch: false,
          output_dir: "lib",
          require_paths: config.require_paths.dup
        }
      end

      def setup_option_parser(opts)
        opts.on("--fetch", "Download configured JAR dependencies (JVM)") do
          options[:fetch] = true
        end

        opts.on("-d", "--dir DIR", "Output directory for --fetch (default: lib)") do |dir|
          options[:output_dir] = dir
        end

        opts.on("-I", "--require-path PATH", "Add require search path") do |path|
          options[:require_paths] << path
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito deps [options] [source.rb]

          Examples:
            konpeito deps src/main.rb          Show dependency analysis
            konpeito deps --fetch              Download configured JAR dependencies
        BANNER
      end

      private

      def find_default_source
        candidates = ["src/main.rb", "main.rb", "app.rb"]
        candidates.find { |f| File.exist?(f) }
      end

      def option_parser_help
        parser = OptionParser.new do |opts|
          opts.banner = banner
          opts.separator ""
          opts.separator "Options:"
          setup_option_parser(opts)
        end
        parser.to_s
      end

      def analyze(source_file)
        emit("Analyzing", source_file)

        resolver = DependencyResolver.new(
          base_paths: options[:require_paths],
          verbose: options[:verbose]
        )

        begin
          _merged_ast, rbs_paths, stdlib_requires, native_extensions = resolver.resolve(source_file)
        rescue Konpeito::DependencyError => e
          display_dependency_error(e)
          exit 1
        end

        resolved = resolver.resolved_files.keys
        puts ""

        # Source files (dependency order)
        puts "Source files (#{resolved.size}):"
        resolved.each_with_index do |path, i|
          puts "  #{i + 1}. #{abbreviate(path)}"
        end

        # Type definitions
        puts ""
        puts "Type definitions (#{rbs_paths.size}):"
        if rbs_paths.empty?
          puts "  (none)"
        else
          rbs_paths.each { |p| puts "  - #{abbreviate(p)}" }
        end

        # Runtime requires
        puts ""
        puts "Runtime requires (#{stdlib_requires.size}):"
        if stdlib_requires.empty?
          puts "  (none)"
        else
          stdlib_requires.each { |r| puts "  - #{r}" }
        end

        # Native extensions
        puts ""
        puts "Native extensions (#{native_extensions.size}):"
        if native_extensions.empty?
          puts "  (none)"
        else
          native_extensions.each { |ext| puts "  - #{ext[:base]}" }
        end
      end

      # Shorten absolute paths relative to cwd for readability
      def abbreviate(path)
        cwd = Dir.pwd + "/"
        path.start_with?(cwd) ? path.delete_prefix(cwd) : path
      end

      # --- JAR fetch (legacy, --fetch) ---

      def fetch_jars
        jars = config.deps_jars

        if jars.empty?
          puts "No dependencies configured in konpeito.toml [deps] section."
          puts ""
          puts "Example:"
          puts '  [deps]'
          puts '  jars = ["com.google.code.gson:gson:2.10.1"]'
          return
        end

        lib_dir = options[:output_dir]
        FileUtils.mkdir_p(lib_dir)

        jars.each do |spec|
          download_jar(spec, lib_dir)
        end

        puts ""
        puts "#{jars.size} dependency(ies) downloaded to #{lib_dir}/"
      end

      def download_jar(spec, lib_dir)
        parts = spec.split(":")
        unless parts.size == 3
          $stderr.puts "Invalid dependency format: #{spec} (expected group:artifact:version)"
          return
        end

        group, artifact, version = parts
        group_path = group.gsub(".", "/")
        filename = "#{artifact}-#{version}.jar"
        dest = File.join(lib_dir, filename)

        if File.exist?(dest)
          puts_verbose "Already downloaded: #{filename}"
          return
        end

        url = "#{MAVEN_CENTRAL_BASE}/#{group_path}/#{artifact}/#{version}/#{filename}"
        puts "Downloading #{spec}..."
        puts_verbose "  URL: #{url}"

        begin
          download_file(url, dest)
          puts "  -> #{dest}"
        rescue => e
          $stderr.puts "  Failed to download #{spec}: #{e.message}"
          FileUtils.rm_f(dest)
        end
      end

      def download_file(url, dest)
        uri = URI(url)
        max_redirects = 5
        redirects = 0

        loop do
          response = Net::HTTP.get_response(uri)

          case response
          when Net::HTTPSuccess
            File.binwrite(dest, response.body)
            return
          when Net::HTTPRedirection
            redirects += 1
            raise "Too many redirects" if redirects > max_redirects
            uri = URI(response["location"])
          else
            raise "HTTP #{response.code}: #{response.message}"
          end
        end
      end
    end
  end
end
