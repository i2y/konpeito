# frozen_string_literal: true

module Conformance
  class TagManager
    TAGS_DIR = File.expand_path("../../tags", __dir__)

    def initialize
      @tags = { native: {}, jvm: {} }
      load_tags
    end

    def known_failure?(backend, spec_name, test_desc)
      tag_set = @tags[backend]&.[](spec_name)
      return false unless tag_set
      tag_set.include?(test_desc)
    end

    def known_failures(backend, spec_name)
      @tags[backend]&.[](spec_name) || []
    end

    def add_tag(backend, spec_name, test_desc)
      @tags[backend] ||= {}
      @tags[backend][spec_name] ||= Set.new
      @tags[backend][spec_name] << test_desc
      save_tags(backend, spec_name)
    end

    def remove_tag(backend, spec_name, test_desc)
      return unless @tags[backend]&.[](spec_name)
      @tags[backend][spec_name].delete(test_desc)
      save_tags(backend, spec_name)
    end

    private

    def load_tags
      [:native, :jvm].each do |backend|
        dir = File.join(TAGS_DIR, backend.to_s)
        next unless File.directory?(dir)

        Dir.glob(File.join(dir, "*.txt")).each do |file|
          spec_name = File.basename(file, ".txt")
          lines = File.readlines(file).map(&:strip).reject(&:empty?).reject { |l| l.start_with?("#") }
          @tags[backend][spec_name] = Set.new(lines)
        end
      end
    end

    def save_tags(backend, spec_name)
      dir = File.join(TAGS_DIR, backend.to_s)
      FileUtils.mkdir_p(dir)
      file = File.join(dir, "#{spec_name}.txt")

      tags = @tags[backend][spec_name]
      if tags.nil? || tags.empty?
        File.delete(file) if File.exist?(file)
      else
        File.write(file, tags.sort.join("\n") + "\n")
      end
    end
  end
end
