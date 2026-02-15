# frozen_string_literal: true

module Konpeito
  module Commands
    # LSP command - starts the Language Server Protocol server
    class LspCommand < BaseCommand
      def self.command_name
        "lsp"
      end

      def self.description
        "Start Language Server Protocol server for IDE integration"
      end

      def run
        parse_options!
        start_lsp_server
      end

      protected

      def setup_option_parser(opts)
        super
      end

      def banner
        "Usage: konpeito lsp [options]"
      end

      private

      def start_lsp_server
        puts_verbose "Starting LSP server..."
        require_relative "../lsp/server"
        server = LSP::Server.new
        server.start
      end
    end
  end
end
