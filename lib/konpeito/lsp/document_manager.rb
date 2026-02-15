# frozen_string_literal: true

require "prism"
require "uri"

module Konpeito
  module LSP
    # Manages open documents, their ASTs, and type information
    class DocumentManager
      def initialize(transport)
        @transport = transport
        @documents = {}  # uri => DocumentState
      end

      # Open a document and analyze it
      # @param uri [String] The document URI
      # @param content [String] The document content
      def open(uri, content)
        analyze(uri, content)
        publish_diagnostics(uri)
      end

      # Update a document and re-analyze
      # @param uri [String] The document URI
      # @param content [String] The new content
      def change(uri, content)
        analyze(uri, content)
        publish_diagnostics(uri)
      end

      # Close a document
      # @param uri [String] The document URI
      def close(uri)
        @documents.delete(uri)
        # Clear diagnostics
        @transport.notify("textDocument/publishDiagnostics", {
          uri: uri,
          diagnostics: []
        })
      end

      # Get document state
      # @param uri [String] The document URI
      # @return [DocumentState, nil]
      def get(uri)
        @documents[uri]
      end

      # Handle hover request
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @return [Hash, nil] Hover response or nil
      def hover(uri, position)
        doc = @documents[uri]
        return nil unless doc&.hm_inferrer

        # Convert LSP position (0-indexed) to Prism position (1-indexed line)
        line = position[:line] + 1
        column = position[:character]

        # Find the node at position
        node = find_node_at_position(doc.ast, line, column)
        return nil unless node

        # Get type information based on node type
        type_string = get_type_info(doc, node)
        return nil unless type_string

        {
          contents: {
            kind: "markdown",
            value: "```ruby\n#{type_string}\n```"
          },
          range: node_to_lsp_range(node)
        }
      end

      # Get type information for a node
      def get_type_info(doc, node)
        hm = doc.hm_inferrer

        case node
        when Prism::DefNode
          # For method definitions, look up the function type
          func_types = hm.instance_variable_get(:@function_types)
          func_type = func_types[node.name]
          if func_type
            final_type = hm.finalize(func_type)
            "def #{node.name}: #{format_type(final_type)}"
          else
            "def #{node.name}"
          end
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode
          # For local variables, look up from environment
          var_name = node.name
          env = hm.instance_variable_get(:@env).first
          scheme = env[var_name]
          if scheme
            final_type = hm.finalize(scheme.type)
            "#{var_name}: #{format_type(final_type)}"
          else
            type = hm.type_for(node)
            type ? format_type(hm.finalize(type)) : nil
          end
        when Prism::CallNode
          # For method calls, show the return type
          type = hm.type_for(node)
          if type
            final_type = hm.finalize(type)
            format_type(final_type)
          end
        else
          # Default: try to get type from node
          type = hm.type_for(node)
          if type
            final_type = hm.finalize(type)
            format_type(final_type)
          end
        end
      end

      # Handle completion request
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @return [Hash] Completion response
      def completion(uri, position)
        doc = @documents[uri]
        return { isIncomplete: false, items: [] } unless doc

        line = position[:line] + 1
        column = position[:character]

        # Get the text before cursor to determine completion context
        lines = doc.content.split("\n")
        current_line = lines[position[:line]] || ""
        text_before_cursor = current_line[0...column]

        items = []

        # Check if we're completing after a "."
        if text_before_cursor =~ /(\w+)\.\s*$/
          receiver_name = $1
          items = complete_methods_for_receiver(doc, receiver_name, line, column)
        else
          # Complete variables and methods from scope
          items = complete_from_scope(doc)
        end

        { isIncomplete: false, items: items }
      end

      # Handle definition request (go to definition)
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @return [Hash, Array, nil] Location or array of locations
      def definition(uri, position)
        doc = @documents[uri]
        return nil unless doc&.ast

        line = position[:line] + 1
        column = position[:character]

        # Find the node at position
        node = find_node_at_position(doc.ast, line, column)
        return nil unless node

        # Find the definition based on node type
        case node
        when Prism::CallNode
          # Find method definition
          method_name = node.name
          def_node = find_method_definition(doc.ast, method_name)
          if def_node
            {
              uri: uri,
              range: node_to_lsp_range(def_node)
            }
          end
        when Prism::LocalVariableReadNode
          # Find variable assignment
          var_name = node.name
          write_node = find_variable_definition(doc.ast, var_name, line)
          if write_node
            {
              uri: uri,
              range: node_to_lsp_range(write_node)
            }
          end
        else
          nil
        end
      end

      # Handle references request (find all references)
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @param include_declaration [Boolean] Whether to include the declaration
      # @return [Array<Hash>] Array of Location objects
      def references(uri, position, include_declaration: true)
        doc = @documents[uri]
        return [] unless doc&.ast

        line = position[:line] + 1
        column = position[:character]

        # Find the node at position
        node = find_node_at_position(doc.ast, line, column)
        return [] unless node

        # Find all references based on node type
        case node
        when Prism::CallNode
          # Find all calls to this method
          method_name = node.name
          finder = ReferenceFinder.new(method_name, :method)
          finder.visit(doc.ast)
          locations = finder.found_nodes.map do |ref_node|
            { uri: uri, range: node_to_lsp_range(ref_node) }
          end

          # Include definition if requested
          if include_declaration
            def_node = find_method_definition(doc.ast, method_name)
            if def_node
              locations.unshift({ uri: uri, range: node_to_lsp_range(def_node) })
            end
          end

          locations
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode
          # Find all usages of this variable
          var_name = node.name
          finder = ReferenceFinder.new(var_name, :variable)
          finder.visit(doc.ast)
          finder.found_nodes.map do |ref_node|
            { uri: uri, range: node_to_lsp_range(ref_node) }
          end
        when Prism::DefNode
          # Find all calls to this method
          method_name = node.name
          finder = ReferenceFinder.new(method_name, :method)
          finder.visit(doc.ast)
          locations = finder.found_nodes.map do |ref_node|
            { uri: uri, range: node_to_lsp_range(ref_node) }
          end

          # Include the definition itself if requested
          if include_declaration
            locations.unshift({ uri: uri, range: node_to_lsp_range(node) })
          end

          locations
        else
          []
        end
      end

      # Handle rename request
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @param new_name [String] The new name for the symbol
      # @return [Hash, nil] WorkspaceEdit or nil if rename not possible
      def rename(uri, position, new_name)
        doc = @documents[uri]
        return nil unless doc&.ast

        line = position[:line] + 1
        column = position[:character]

        # Find the node at position
        node = find_node_at_position(doc.ast, line, column)
        return nil unless node

        # Get the current name and find all references
        current_name, refs = case node
        when Prism::CallNode
          method_name = node.name
          finder = ReferenceFinder.new(method_name, :method)
          finder.visit(doc.ast)

          # Also include the definition
          def_node = find_method_definition(doc.ast, method_name)
          refs = finder.found_nodes.dup
          refs.unshift(def_node) if def_node

          [method_name.to_s, refs]
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode
          var_name = node.name
          finder = ReferenceFinder.new(var_name, :variable)
          finder.visit(doc.ast)
          [var_name.to_s, finder.found_nodes]
        when Prism::DefNode
          method_name = node.name
          finder = ReferenceFinder.new(method_name, :method)
          finder.visit(doc.ast)

          # Include the definition itself
          refs = [node] + finder.found_nodes

          [method_name.to_s, refs]
        else
          return nil
        end

        return nil if refs.empty?

        # Build text edits - calculate the range for just the name part
        text_edits = refs.map do |ref_node|
          range = name_range_for_node(ref_node, current_name)
          { range: range, newText: new_name }
        end

        # Return WorkspaceEdit
        {
          changes: {
            uri => text_edits
          }
        }
      end

      # Prepare rename - check if rename is valid and return the current name range
      # @param uri [String] The document URI
      # @param position [Hash] The position { line:, character: }
      # @return [Hash, nil] Range and placeholder text
      def prepare_rename(uri, position)
        doc = @documents[uri]
        return nil unless doc&.ast

        line = position[:line] + 1
        column = position[:character]

        node = find_node_at_position(doc.ast, line, column)
        return nil unless node

        case node
        when Prism::CallNode
          name = node.name.to_s
          { range: name_range_for_node(node, name), placeholder: name }
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode
          name = node.name.to_s
          { range: name_range_for_node(node, name), placeholder: name }
        when Prism::DefNode
          name = node.name.to_s
          { range: name_range_for_node(node, name), placeholder: name }
        else
          nil
        end
      end

      private

      # Get the LSP range for just the name part of a node
      def name_range_for_node(node, name)
        case node
        when Prism::DefNode
          # For def nodes, the name starts after "def "
          loc = node.name_loc
          {
            start: { line: loc.start_line - 1, character: loc.start_column },
            end: { line: loc.end_line - 1, character: loc.end_column }
          }
        when Prism::CallNode
          # For call nodes, use the message_loc
          loc = node.message_loc
          if loc
            {
              start: { line: loc.start_line - 1, character: loc.start_column },
              end: { line: loc.end_line - 1, character: loc.end_column }
            }
          else
            node_to_lsp_range(node)
          end
        when Prism::LocalVariableReadNode, Prism::LocalVariableWriteNode
          # For variables, the whole node is the name
          loc = node.location
          {
            start: { line: loc.start_line - 1, character: loc.start_column },
            end: { line: loc.start_line - 1, character: loc.start_column + name.length }
          }
        else
          node_to_lsp_range(node)
        end
      end

      # Complete methods based on receiver type
      def complete_methods_for_receiver(doc, receiver_name, line, column)
        return [] unless doc.hm_inferrer

        hm = doc.hm_inferrer
        env = hm.instance_variable_get(:@env).first
        scheme = env[receiver_name.to_sym]

        return [] unless scheme

        type = hm.finalize(scheme.type)
        types_mod = TypeChecker::Types

        items = []

        case type
        when types_mod::ClassInstance
          # Get methods for this class from RBS or built-in
          methods = get_methods_for_type(type.name)
          items = methods.map do |method_name, signature|
            {
              label: method_name.to_s,
              kind: 2,  # Method
              detail: signature
            }
          end
        end

        items
      end

      # Complete variables and methods from current scope
      def complete_from_scope(doc)
        items = []

        if doc.hm_inferrer
          hm = doc.hm_inferrer
          env = hm.instance_variable_get(:@env).first
          func_types = hm.instance_variable_get(:@function_types)

          # Add variables
          env.each do |name, scheme|
            type = hm.finalize(scheme.type)
            kind = type.is_a?(TypeChecker::FunctionType) ? 3 : 6  # Function or Variable
            items << {
              label: name.to_s,
              kind: kind,
              detail: format_type(type)
            }
          end

          # Add function definitions
          func_types.each do |name, func_type|
            next if env.key?(name)  # Already added
            items << {
              label: name.to_s,
              kind: 3,  # Function
              detail: format_type(hm.finalize(func_type))
            }
          end
        end

        items
      end

      # Get methods for a type (from built-in knowledge)
      def get_methods_for_type(type_name)
        # Basic built-in methods for common types
        case type_name.to_sym
        when :Integer
          {
            to_s: "() -> String",
            to_f: "() -> Float",
            abs: "() -> Integer",
            times: "{ (Integer) -> void } -> Integer"
          }
        when :Float
          {
            to_s: "() -> String",
            to_i: "() -> Integer",
            abs: "() -> Float",
            round: "() -> Integer",
            floor: "() -> Integer",
            ceil: "() -> Integer"
          }
        when :String
          {
            to_s: "() -> String",
            to_i: "() -> Integer",
            length: "() -> Integer",
            size: "() -> Integer",
            upcase: "() -> String",
            downcase: "() -> String",
            strip: "() -> String"
          }
        when :Array
          {
            length: "() -> Integer",
            size: "() -> Integer",
            first: "() -> T",
            last: "() -> T",
            push: "(T) -> Array",
            pop: "() -> T",
            map: "{ (T) -> U } -> Array[U]",
            each: "{ (T) -> void } -> Array"
          }
        when :Hash
          {
            keys: "() -> Array",
            values: "() -> Array",
            size: "() -> Integer",
            empty?: "() -> bool"
          }
        else
          {}
        end
      end

      # Find method definition in AST
      def find_method_definition(ast, method_name)
        finder = DefinitionFinder.new(method_name, :method)
        finder.visit(ast)
        finder.found_node
      end

      # Find variable definition (first assignment)
      def find_variable_definition(ast, var_name, before_line)
        finder = DefinitionFinder.new(var_name, :variable, before_line)
        finder.visit(ast)
        finder.found_node
      end

      # Analyze a document and store results
      def analyze(uri, content)
        file_path = uri_to_path(uri)

        # Parse with Prism
        parse_result = Prism.parse(content)
        ast = parse_result.value
        parse_errors = parse_result.errors

        # Initialize RBS loader
        rbs_loader = TypeChecker::RBSLoader.new

        # Load RBS files if they exist
        rbs_path = file_path.sub(/\.rb$/, ".rbs")
        if File.exist?(rbs_path)
          rbs_loader.load(rbs_paths: [rbs_path])
        else
          rbs_loader.load(rbs_paths: [])
        end

        # Build typed AST with HM inference
        builder = AST::TypedASTBuilder.new(
          rbs_loader,
          use_hm: true,
          file_path: file_path,
          source: content
        )

        typed_ast = nil
        hm_inferrer = nil
        diagnostics = []

        begin
          typed_ast = builder.build(ast)
          hm_inferrer = builder.instance_variable_get(:@hm_inferrer)
          diagnostics = builder.diagnostics
        rescue StandardError => e
          # If type checking fails, still store the AST
          diagnostics << Diagnostics::Diagnostic.new(
            severity: :error,
            code: "E100",
            message: "Type checking error: #{e.message}"
          )
        end

        # Add parse errors to diagnostics
        parse_errors.each do |error|
          span = if error.location
            Diagnostics::SourceSpan.new(
              file_path: file_path,
              start_line: error.location.start_line,
              start_column: error.location.start_column,
              end_line: error.location.end_line,
              end_column: error.location.end_column,
              source: content
            )
          end

          diagnostics << Diagnostics::Diagnostic.new(
            severity: :error,
            code: "E010",
            message: error.message,
            span: span
          )
        end

        @documents[uri] = DocumentState.new(
          content: content,
          ast: ast,
          typed_ast: typed_ast,
          hm_inferrer: hm_inferrer,
          diagnostics: diagnostics
        )
      end

      # Publish diagnostics to the client
      def publish_diagnostics(uri)
        doc = @documents[uri]
        return unless doc

        lsp_diagnostics = doc.diagnostics.map do |diag|
          {
            range: span_to_lsp_range(diag.span),
            severity: severity_to_lsp(diag.severity),
            code: diag.code,
            source: "konpeito",
            message: diag.message
          }
        end

        @transport.notify("textDocument/publishDiagnostics", {
          uri: uri,
          diagnostics: lsp_diagnostics
        })
      end

      # Convert file URI to path
      def uri_to_path(uri)
        if uri.start_with?("file://")
          URI.decode_www_form_component(uri.sub("file://", ""))
        else
          uri
        end
      end

      # Convert diagnostic severity to LSP severity
      def severity_to_lsp(severity)
        case severity
        when :error then 1
        when :warning then 2
        when :note, :info then 3
        when :help, :hint then 4
        else 1
        end
      end

      # Convert SourceSpan to LSP range
      def span_to_lsp_range(span)
        return { start: { line: 0, character: 0 }, end: { line: 0, character: 0 } } unless span

        {
          start: { line: span.start_line - 1, character: span.start_column },
          end: { line: (span.end_line || span.start_line) - 1, character: span.end_column || span.start_column }
        }
      end

      # Convert Prism node to LSP range
      def node_to_lsp_range(node)
        return nil unless node.respond_to?(:location) && node.location

        loc = node.location
        {
          start: { line: loc.start_line - 1, character: loc.start_column },
          end: { line: loc.end_line - 1, character: loc.end_column }
        }
      end

      # Find the most specific node at a given position
      def find_node_at_position(ast, line, column)
        return nil unless ast

        visitor = NodeFinder.new(line, column)
        visitor.visit(ast)
        visitor.found_node
      end

      # Format type for display
      def format_type(type)
        types_mod = TypeChecker::Types

        case type
        when TypeChecker::TypeVar
          type.instance ? format_type(type.instance) : type.to_s
        when TypeChecker::FunctionType
          params = type.param_types.map { |t| format_type(t) }.join(", ")
          "(#{params}) -> #{format_type(type.return_type)}"
        when types_mod::ClassInstance
          if type.type_args.empty?
            type.name.to_s
          else
            args = type.type_args.map { |a| format_type(a) }.join(", ")
            "#{type.name}[#{args}]"
          end
        when types_mod::Union
          type.types.map { |t| format_type(t) }.join(" | ")
        when types_mod::NativeClassType
          "#{type.class_name} (native)"
        else
          type.to_s
        end
      end

      # Document state container
      DocumentState = Struct.new(
        :content,
        :ast,
        :typed_ast,
        :hm_inferrer,
        :diagnostics,
        keyword_init: true
      )

      # Visitor to find node at position
      class NodeFinder
        attr_reader :found_node

        def initialize(line, column)
          @target_line = line
          @target_column = column
          @found_node = nil
        end

        def visit(node)
          return unless node

          # Check if this node contains the target position
          if node.respond_to?(:location) && node.location && position_in_range?(node.location)
            @found_node = node
          end

          # Visit all child nodes
          visit_children(node)
        end

        private

        def visit_children(node)
          node.child_nodes.each do |child|
            visit(child) if child
          end
        end

        def position_in_range?(loc)
          start_ok = loc.start_line < @target_line ||
                     (loc.start_line == @target_line && loc.start_column <= @target_column)
          end_ok = loc.end_line > @target_line ||
                   (loc.end_line == @target_line && loc.end_column >= @target_column)
          start_ok && end_ok
        end
      end

      # Visitor to find definition of a method or variable
      class DefinitionFinder
        attr_reader :found_node

        def initialize(name, kind, before_line = nil)
          @name = name.to_sym
          @kind = kind
          @before_line = before_line
          @found_node = nil
        end

        def visit(node)
          return unless node

          case @kind
          when :method
            if node.is_a?(Prism::DefNode) && node.name == @name
              @found_node = node
            end
          when :variable
            if node.is_a?(Prism::LocalVariableWriteNode) && node.name == @name
              # Only find definitions before the reference line
              if @before_line.nil? || node.location.start_line < @before_line
                @found_node ||= node  # Keep first occurrence
              end
            end
          end

          # Visit children
          visit_children(node)
        end

        private

        def visit_children(node)
          node.child_nodes.each do |child|
            visit(child) if child
          end
        end
      end

      # Finds all references to a symbol (variable or method)
      class ReferenceFinder
        attr_reader :found_nodes

        def initialize(name, kind)
          @name = name.to_sym
          @kind = kind
          @found_nodes = []
        end

        def visit(node)
          return unless node

          case @kind
          when :method
            # Find method calls
            if node.is_a?(Prism::CallNode) && node.name == @name
              @found_nodes << node
            end
          when :variable
            # Find variable reads and writes
            if (node.is_a?(Prism::LocalVariableReadNode) || node.is_a?(Prism::LocalVariableWriteNode)) &&
               node.name == @name
              @found_nodes << node
            end
          end

          # Visit children
          visit_children(node)
        end

        private

        def visit_children(node)
          node.child_nodes.each do |child|
            visit(child) if child
          end
        end
      end
    end
  end
end
