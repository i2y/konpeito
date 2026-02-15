# frozen_string_literal: true

module Konpeito
  module Commands
    # Watch command - watch for file changes and recompile
    class WatchCommand < BaseCommand
      def self.command_name
        "watch"
      end

      def self.description
        "Watch for file changes and recompile automatically"
      end

      def run
        parse_options!

        unless listen_available?
          error("The 'listen' gem is required for watch mode. Install it with 'gem install listen'.")
        end

        require "listen"

        @source_file = args.first
        if @source_file && !File.exist?(@source_file)
          error("File not found: #{@source_file}")
        end

        start_watching
      end

      protected

      def default_options
        {
          verbose: false,
          color: $stderr.tty?,
          output: config.build_output,
          format: config.build_format,
          paths: config.watch_paths,
          extensions: config.watch_extensions,
          clear: true
        }
      end

      def setup_option_parser(opts)
        opts.on("-o", "--output FILE", "Output file name") do |file|
          options[:output] = file
        end

        opts.on("-w", "--watch PATH", "Additional paths to watch (can be used multiple times)") do |path|
          options[:paths] << path
        end

        opts.on("--no-clear", "Do not clear screen before each rebuild") do
          options[:clear] = false
        end

        super
      end

      def banner
        <<~BANNER.chomp
          Usage: konpeito watch [options] [source.rb]

          Examples:
            konpeito watch src/main.rb                 Watch and recompile
            konpeito watch -w lib src/main.rb          Watch additional paths
        BANNER
      end

      private

      def listen_available?
        require "listen"
        true
      rescue LoadError
        false
      end

      def start_watching
        watch_paths = options[:paths].select { |p| Dir.exist?(p) }

        if watch_paths.empty?
          watch_paths = ["."]
        end

        timestamp = Time.now.strftime("%H:%M:%S")
        emit("Watching", "#{watch_paths.join(', ')} [#{options[:extensions].join(', ')}]")
        $stderr.puts ""

        # Initial build
        if @source_file
          rebuild
        end

        # Start watching
        extensions_pattern = /\.(#{options[:extensions].join('|')})$/

        listener = Listen.to(*watch_paths) do |modified, added, removed|
          changed_files = (modified + added + removed).select { |f| f.match?(extensions_pattern) }

          unless changed_files.empty?
            $stderr.puts ""
            changed_files.each do |f|
              emit("Changed", File.basename(f))
            end
            rebuild
          end
        end

        listener.start

        # Keep running
        begin
          sleep
        rescue Interrupt
          $stderr.puts ""
          emit("Stopped", "watch mode")
          listener.stop
        end
      end

      def rebuild
        clear_screen if options[:clear]

        if @source_file
          compile_single(@source_file)
        else
          compile_all
        end
      end

      def compile_single(source_file)
        output_file = options[:output] || default_output_name(source_file, format: options[:format])

        emit("Compiling", "#{source_file} (native)")

        compiler = Compiler.new(
          source_file: source_file,
          output_file: output_file,
          format: options[:format],
          verbose: options[:verbose],
          rbs_paths: config.rbs_paths,
          require_paths: config.require_paths,
          incremental: true
        )

        compiler.compile
        display_diagnostics(compiler.diagnostics)

        if compiler.diagnostics.any?(&:error?)
          error_count = compiler.diagnostics.count(&:error?)
          emit_error("Failed", "with #{error_count} error(s)")
        else
          stats = compiler.compile_stats
          if stats
            duration_str = "%.2fs" % stats.duration_s
            emit("Finished", "in #{duration_str} -> #{output_file}")
          end
        end
      rescue Konpeito::Error => e
        $stderr.puts "Error: #{e.message}"
        emit_error("Failed", "build error")
      end

      def compile_all
        src_files = Dir.glob("src/**/*.rb")

        if src_files.empty?
          puts "No source files found in src/"
          return
        end

        success_count = 0
        error_count = 0

        src_files.each do |source_file|
          begin
            output_file = default_output_name(source_file, format: options[:format])
            compiler = Compiler.new(
              source_file: source_file,
              output_file: output_file,
              format: options[:format],
              verbose: options[:verbose],
              rbs_paths: config.rbs_paths,
              require_paths: config.require_paths,
              incremental: true
            )
            compiler.compile

            if compiler.diagnostics.any?(&:error?)
              display_diagnostics(compiler.diagnostics)
              error_count += 1
            else
              success_count += 1
            end
          rescue Konpeito::Error => e
            $stderr.puts "Error compiling #{source_file}: #{e.message}"
            error_count += 1
          end
        end

        puts "Build complete: #{success_count} succeeded, #{error_count} failed"
      end

      def clear_screen
        print "\e[2J\e[H"
      end
    end
  end
end
