# frozen_string_literal: true

require "rbs/inline"

module Konpeito
  module RBSInline
    # Extracts inline RBS annotations from Ruby source and generates RBS files
    # Uses rbs-inline to generate base RBS, then merges Konpeito-specific annotations
    #
    # Supported annotations in Ruby source:
    #   # rbs_inline: enabled  (required magic comment)
    #   # @rbs %a{native}      (Konpeito annotation on class/module)
    #   # @rbs %a{cfunc: "sin"} (Konpeito annotation on method)
    #   # @rbs @x: Float       (instance variable type - standard rbs-inline)
    #   #: (Float) -> Float    (method type - standard rbs-inline)
    class Preprocessor
      # Check if a Ruby source file has inline RBS annotations
      # @param source [String] Ruby source code
      # @return [Boolean]
      def self.has_inline_rbs?(source)
        source.include?("# rbs_inline: enabled")
      end

      # Process a Ruby source file and generate RBS content with Konpeito annotations
      # @param source [String] Ruby source code
      # @param filename [String] Source filename for error messages
      # @return [String] Generated RBS content with Konpeito annotations merged
      def process(source, filename: "(inline)")
        @source = source
        @filename = filename

        # Step 1: Extract Konpeito-specific annotations (# @rbs %a{...})
        konpeito_annotations = extract_konpeito_annotations(source)

        # Step 2: Run rbs-inline to generate base RBS
        base_rbs = run_rbs_inline(source, filename)

        # Step 3: Merge Konpeito annotations into generated RBS
        merge_annotations(base_rbs, konpeito_annotations)
      end

      private

      # Extract # @rbs %a{...} annotations and their target declarations
      # Returns a hash of { "ClassName" => [annotations], "ClassName#method" => [annotations] }
      def extract_konpeito_annotations(source)
        annotations = {}
        lines = source.lines
        pending_annotations = []

        lines.each_with_index do |line, idx|
          stripped = line.strip

          # Collect Konpeito annotations
          if stripped.start_with?("# @rbs %a{")
            if match = stripped.match(/^#\s*@rbs\s+(%a\{[^}]+\})/)
              pending_annotations << match[1]
            end
          # Match class definition
          elsif stripped.match?(/^class\s+(\w+)/)
            if match = stripped.match(/^class\s+(\w+)/)
              class_name = match[1]
              annotations[class_name] = pending_annotations.dup unless pending_annotations.empty?
              pending_annotations.clear
            end
          # Match module definition
          elsif stripped.match?(/^module\s+(\w+)/)
            if match = stripped.match(/^module\s+(\w+)/)
              module_name = match[1]
              annotations[module_name] = pending_annotations.dup unless pending_annotations.empty?
              pending_annotations.clear
            end
          # Match method definition
          elsif stripped.match?(/^def\s+(self\.)?(\w+[?!=]?)/)
            if match = stripped.match(/^def\s+(self\.)?(\w+[?!=]?)/)
              # Find the current class/module context by looking back
              context = find_current_context(lines, idx)
              if context
                singleton = match[1] ? "." : "#"
                method_name = match[2]
                key = "#{context}#{singleton}#{method_name}"
                annotations[key] = pending_annotations.dup unless pending_annotations.empty?
              end
              pending_annotations.clear
            end
          # Clear pending on non-annotation, non-empty lines
          elsif !stripped.empty? && !stripped.start_with?("#")
            pending_annotations.clear
          end
        end

        annotations
      end

      # Find the class/module context for a given line
      def find_current_context(lines, current_idx)
        indent_stack = []

        (0...current_idx).each do |idx|
          line = lines[idx]
          stripped = line.strip

          if stripped.match?(/^class\s+(\w+)/)
            match = stripped.match(/^class\s+(\w+)/)
            indent_stack << match[1]
          elsif stripped.match?(/^module\s+(\w+)/)
            match = stripped.match(/^module\s+(\w+)/)
            indent_stack << match[1]
          elsif stripped == "end"
            indent_stack.pop
          end
        end

        indent_stack.last
      end

      # Run rbs-inline as library to generate base RBS (no subprocess)
      def run_rbs_inline(source, _filename)
        prism_result = Prism.parse(source)
        parsed = RBS::Inline::Parser.parse(prism_result, opt_in: true)
        return "" unless parsed

        uses, decls, rbs_decls = parsed
        writer = RBS::Inline::Writer.new
        writer.write(uses, decls, rbs_decls)
        writer.output || ""
      rescue => e
        warn "Warning: rbs-inline failed for #{_filename}: #{e.message}"
        ""
      end

      # Merge Konpeito annotations into generated RBS
      def merge_annotations(rbs_content, konpeito_annotations)
        # First, clean up rbs-inline output (remove # @rbs comments and duplicate %a{})
        cleaned_lines = []
        rbs_content.lines.each do |line|
          stripped = line.strip
          # Skip comment lines with @rbs or redundant %a{} lines from rbs-inline
          next if stripped.start_with?("# @rbs")
          next if stripped.start_with?("# :")
          next if stripped.match?(/^%a\{[^}]+\}$/) && !stripped.match?(/^%a\{(deprecated|pure)/)
          cleaned_lines << line
        end

        return cleaned_lines.join if konpeito_annotations.empty?

        lines = cleaned_lines
        result = []
        current_context = []

        lines.each do |line|
          stripped = line.strip

          # Track class/module context
          if stripped.match?(/^class\s+(\w+)/)
            match = stripped.match(/^class\s+(\w+)/)
            class_name = match[1]
            current_context << class_name

            # Insert class annotations before class definition
            if anns = konpeito_annotations[class_name]
              anns.each { |ann| result << "#{ann}\n" }
            end
          elsif stripped.match?(/^module\s+(\w+)/)
            match = stripped.match(/^module\s+(\w+)/)
            module_name = match[1]
            current_context << module_name

            # Insert module annotations before module definition
            if anns = konpeito_annotations[module_name]
              anns.each { |ann| result << "#{ann}\n" }
            end
          elsif stripped == "end"
            current_context.pop
          elsif stripped.match?(/^def\s+(self\.)?(\w+[?!=]?):/)
            # Method definition in RBS
            match = stripped.match(/^def\s+(self\.)?(\w+[?!=]?):/)
            singleton = match[1] ? "." : "#"
            method_name = match[2]
            context = current_context.last

            if context
              key = "#{context}#{singleton}#{method_name}"
              if anns = konpeito_annotations[key]
                # Get the indentation from the current line
                indent = line[/^\s*/]
                anns.each { |ann| result << "#{indent}#{ann}\n" }
              end
            end
          end

          result << line
        end

        result.join
      end
    end
  end
end
