# frozen_string_literal: true

require "net/http"
require "fileutils"

module Konpeito
  module Commands
    # Deps command - download Maven dependencies
    class DepsCommand < BaseCommand
      MAVEN_CENTRAL_BASE = "https://repo1.maven.org/maven2"

      def self.command_name
        "deps"
      end

      def self.description
        "Download JAR dependencies from Maven Central"
      end

      def run
        parse_options!

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

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          output_dir: "lib"
        }
      end

      def setup_option_parser(opts)
        opts.on("-d", "--dir DIR", "Output directory (default: lib)") do |dir|
          options[:output_dir] = dir
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito deps [options]

          Examples:
            konpeito deps                              Download all configured JARs
            konpeito deps -d vendor/lib                Download to custom directory
        BANNER
      end

      private

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
