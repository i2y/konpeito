# frozen_string_literal: true

require "language_server-protocol"

module Konpeito
  module LSP
    # Handles LSP JSON-RPC communication over stdio
    class Transport
      def initialize(input: $stdin, output: $stdout)
        @reader = LanguageServer::Protocol::Transport::Io::Reader.new(input)
        @writer = LanguageServer::Protocol::Transport::Io::Writer.new(output)
      end

      # Read next request/notification from client
      # @return [Hash, nil] The request object or nil if EOF
      def read
        @reader.read
      end

      # Write response to client
      # @param response [Hash] The response object
      def write(response)
        @writer.write(response)
      end

      # Send notification to client (no response expected)
      # @param method [String] The notification method
      # @param params [Hash] The notification parameters
      def notify(method, params)
        @writer.write({
          jsonrpc: "2.0",
          method: method,
          params: params
        })
      end
    end
  end
end
