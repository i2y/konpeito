# frozen_string_literal: true

module Konpeito
  module TypeChecker
    # Parses %a{...} RBS annotations into structured data
    module AnnotationParser
      module_function

      # Parse a single annotation string into a structured hash
      # @param ann_string [String] The annotation content (without %a{})
      # @return [Hash] Parsed annotation data with :type key
      def parse(ann_string)
        case ann_string.strip
        when /\Anative\z/
          { type: :native }
        when /\Anative:\s*vtable\z/
          { type: :native, vtable: true }
        when /\Aextern\z/
          { type: :extern }
        when /\Aboxed\z/
          { type: :boxed }
        when /\Astruct\z/
          { type: :struct }
        when /\Asimd\z/
          { type: :simd }
        when /\Affi:\s*"([^"]+)"\z/
          { type: :ffi, library: ::Regexp.last_match(1) }
        when /\Acfunc:\s*"([^"]+)"\z/
          { type: :cfunc, c_name: ::Regexp.last_match(1) }
        when /\Acfunc\z/
          { type: :cfunc }
        when /\Ajvm_static:\s*"([^"]+)"\z/
          { type: :jvm_static, java_class: ::Regexp.last_match(1) }
        when /\Acallback:\s*"([^"]+)"\s+descriptor:\s*"([^"]+)"\z/
          { type: :callback, interface: ::Regexp.last_match(1), descriptor: ::Regexp.last_match(2) }
        when /\Acallback:\s*"([^"]+)"\z/
          { type: :callback, interface: ::Regexp.last_match(1) }
        else
          { type: :unknown, raw: ann_string }
        end
      end

      # Parse all annotations from an array of RBS::AST::Annotation
      # @param annotations [Array<RBS::AST::Annotation>] RBS annotations
      # @return [Array<Hash>] Parsed annotation data
      def parse_all(annotations)
        annotations.map { |ann| parse(ann.string) }
      end

      # Find a specific annotation type from parsed annotations
      # @param parsed [Array<Hash>] Parsed annotations
      # @param type [Symbol] Annotation type to find
      # @return [Hash, nil] The found annotation or nil
      def find(parsed, type)
        parsed.find { |ann| ann[:type] == type }
      end

      # Check if annotations contain a specific type
      # @param parsed [Array<Hash>] Parsed annotations
      # @param type [Symbol] Annotation type to check
      # @return [Boolean]
      def has?(parsed, type)
        !find(parsed, type).nil?
      end
    end
  end
end
