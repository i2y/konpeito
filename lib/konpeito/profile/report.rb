# frozen_string_literal: true

require "json"

module Konpeito
  module Profile
    # Represents profiling data for a single function
    class FunctionProfile
      attr_reader :name, :calls, :time_ms, :percent

      def initialize(name:, calls:, time_ms:, percent:)
        @name = name
        @calls = calls
        @time_ms = time_ms
        @percent = percent
      end

      def to_h
        {
          name: @name,
          calls: @calls,
          time_ms: @time_ms,
          percent: @percent
        }
      end
    end

    # Reads and formats profile reports from JSON files
    class Report
      attr_reader :functions, :total_time_ms

      def initialize(json_path)
        raise ArgumentError, "Profile file not found: #{json_path}" unless File.exist?(json_path)

        @json_path = json_path
        data = JSON.parse(File.read(json_path))
        @functions = data["functions"].map do |f|
          FunctionProfile.new(
            name: f["name"],
            calls: f["calls"],
            time_ms: f["time_ms"],
            percent: f["percent"]
          )
        end.sort_by { |f| -f.time_ms }
        @total_time_ms = data["total_time_ms"]
      end

      def to_text(max_name_length: 40)
        lines = []
        lines << "Konpeito Profile Report"
        lines << "=" * 76
        lines << ""
        lines << format("%-#{max_name_length}s %12s %12s %8s", "Function", "Calls", "Time (ms)", "%")
        lines << format("%-#{max_name_length}s %12s %12s %8s",
                        "-" * max_name_length, "-" * 12, "-" * 12, "-" * 8)

        @functions.each do |f|
          name = truncate_name(f.name, max_name_length)
          lines << format("%-#{max_name_length}s %12d %12.3f %7.2f%%",
                          name, f.calls, f.time_ms, f.percent)
        end

        lines << ""
        lines << "Total time: #{@total_time_ms.round(3)} ms"
        lines.join("\n")
      end

      def to_json_pretty
        JSON.pretty_generate({
          functions: @functions.map(&:to_h),
          total_time_ms: @total_time_ms
        })
      end

      def hottest_functions(n = 5)
        @functions.first(n)
      end

      def most_called_functions(n = 5)
        @functions.sort_by { |f| -f.calls }.first(n)
      end

      # Get the path to the flame graph folded file
      def flame_graph_path
        @json_path.sub(/\.json$/, ".folded")
      end

      # Check if flame graph data exists
      def flame_graph_available?
        File.exist?(flame_graph_path)
      end

      # Read flame graph data as array of [stack, samples]
      def flame_graph_stacks
        return [] unless flame_graph_available?

        File.readlines(flame_graph_path).map do |line|
          parts = line.strip.split(" ")
          samples = parts.pop.to_i
          stack = parts.join(" ")
          [stack, samples]
        end.sort_by { |_, samples| -samples }
      end

      # Generate flame graph text summary
      def flame_graph_summary(max_stacks: 10)
        stacks = flame_graph_stacks.first(max_stacks)
        return "No flame graph data available" if stacks.empty?

        lines = []
        lines << "Flame Graph Stack Summary (Top #{max_stacks})"
        lines << "=" * 76
        lines << ""

        total_samples = flame_graph_stacks.sum { |_, s| s }
        stacks.each do |stack, samples|
          percent = total_samples > 0 ? (samples * 100.0 / total_samples) : 0
          lines << format("%7d (%5.1f%%) %s", samples, percent, stack)
        end

        lines << ""
        lines << "To generate flame graph SVG:"
        lines << "  flamegraph.pl #{flame_graph_path} > profile.svg"
        lines.join("\n")
      end

      private

      def truncate_name(name, max_length)
        return name if name.length <= max_length

        "#{name[0, max_length - 3]}..."
      end
    end
  end
end
