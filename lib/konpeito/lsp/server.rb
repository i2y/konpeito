# frozen_string_literal: true

require_relative "transport"
require_relative "document_manager"

module Konpeito
  module LSP
    # Main LSP server that handles client requests
    class Server
      attr_reader :transport, :document_manager

      def initialize(input: $stdin, output: $stdout)
        @transport = Transport.new(input: input, output: output)
        @document_manager = DocumentManager.new(@transport)
        @running = false
        @initialized = false
      end

      # Start the LSP server main loop
      def start
        @running = true
        while @running
          request = @transport.read
          break unless request

          response = handle_request(request)
          @transport.write(response) if response
        end
      end

      # Stop the server
      def stop
        @running = false
      end

      # Handle a single request (exposed for testing)
      # @param request [Hash] The LSP request
      # @return [Hash, nil] The response or nil for notifications
      def handle_request(request)
        method = request[:method]
        id = request[:id]
        params = request[:params] || {}

        result = case method
        when "initialize"
          handle_initialize(params)
        when "initialized"
          # Notification, no response needed
          nil
        when "shutdown"
          handle_shutdown
        when "exit"
          @running = false
          nil
        when "textDocument/didOpen"
          handle_did_open(params)
        when "textDocument/didChange"
          handle_did_change(params)
        when "textDocument/didClose"
          handle_did_close(params)
        when "textDocument/hover"
          handle_hover(params)
        when "textDocument/completion"
          handle_completion(params)
        when "textDocument/definition"
          handle_definition(params)
        when "textDocument/references"
          handle_references(params)
        when "textDocument/rename"
          handle_rename(params)
        when "textDocument/prepareRename"
          handle_prepare_rename(params)
        else
          # Unknown method
          if id
            { error: { code: -32601, message: "Method not found: #{method}" } }
          end
        end

        # Build response for requests (not notifications)
        if id && result != :notification
          { jsonrpc: "2.0", id: id, result: result }
        else
          nil
        end
      end

      private

      def handle_initialize(params)
        @initialized = true

        {
          capabilities: {
            textDocumentSync: {
              openClose: true,
              change: 1  # Full content sync
            },
            hoverProvider: true,
            completionProvider: {
              triggerCharacters: ["."],
              resolveProvider: false
            },
            definitionProvider: true,
            referencesProvider: true,
            renameProvider: {
              prepareProvider: true
            }
          },
          serverInfo: {
            name: "konpeito-lsp",
            version: Konpeito::VERSION
          }
        }
      end

      def handle_shutdown
        @initialized = false
        nil
      end

      def handle_did_open(params)
        uri = params.dig(:textDocument, :uri)
        text = params.dig(:textDocument, :text)
        @document_manager.open(uri, text)
        :notification
      end

      def handle_did_change(params)
        uri = params.dig(:textDocument, :uri)
        # We use full sync, so first contentChanges has full text
        changes = params[:contentChanges]
        text = changes&.first&.dig(:text)
        @document_manager.change(uri, text) if text
        :notification
      end

      def handle_did_close(params)
        uri = params.dig(:textDocument, :uri)
        @document_manager.close(uri)
        :notification
      end

      def handle_hover(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        @document_manager.hover(uri, position)
      end

      def handle_completion(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        @document_manager.completion(uri, position)
      end

      def handle_definition(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        @document_manager.definition(uri, position)
      end

      def handle_references(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        include_declaration = params.dig(:context, :includeDeclaration) != false
        @document_manager.references(uri, position, include_declaration: include_declaration)
      end

      def handle_rename(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        new_name = params[:newName]
        @document_manager.rename(uri, position, new_name)
      end

      def handle_prepare_rename(params)
        uri = params.dig(:textDocument, :uri)
        position = params[:position]
        @document_manager.prepare_rename(uri, position)
      end
    end
  end
end
