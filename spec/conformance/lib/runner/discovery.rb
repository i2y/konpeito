# frozen_string_literal: true

module Conformance
  class Discovery
    SPEC_DIR = File.expand_path("../../language", __dir__)

    def initialize(pattern: nil)
      @pattern = pattern
    end

    def find_specs
      files = Dir.glob(File.join(SPEC_DIR, "*_spec.rb")).sort
      if @pattern
        files = files.select { |f| File.basename(f).include?(@pattern) }
      end
      files
    end
  end
end
