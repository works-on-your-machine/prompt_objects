# frozen_string_literal: true

require "mcp"

module PromptObjects
  module MCP
    # MCP Server exposing PromptObjects functionality
    # This allows any MCP client (Claude Desktop, Go TUI, etc.) to interact with POs
    class Server
      attr_reader :env, :mcp_server

      def initialize(objects_dir: "objects", primitives_dir: nil)
        @objects_dir = objects_dir
        @primitives_dir = primitives_dir
        @env = nil
        @context = nil
      end

      def start
        setup_environment
        setup_mcp_server
        run_stdio_transport
      end

      private

      def setup_environment
        @env = Environment.new(
          objects_dir: @objects_dir,
          primitives_dir: @primitives_dir
        )
        @context = @env.context(tui_mode: true)

        load_all_objects
      end

      def load_all_objects
        return unless Dir.exist?(@objects_dir)

        Dir.glob(File.join(@objects_dir, "*.md")).each do |path|
          @env.load_prompt_object(path)
        rescue StandardError => e
          warn "Failed to load #{path}: #{e.message}"
        end

        @env.registry.prompt_objects.each do |po|
          @env.load_dependencies(po)
        end
      end

      def setup_mcp_server
        # Use 2025-06-18 for compatibility with ruby_llm MCP client
        # which doesn't yet support the latest 2025-11-25 protocol
        configuration = ::MCP::Configuration.new(
          protocol_version: ENV.fetch("MCP_PROTOCOL_VERSION", "2025-06-18")
        )

        @mcp_server = ::MCP::Server.new(
          name: "prompt_objects",
          version: PromptObjects::VERSION,
          tools: build_tools,
          server_context: { env: @env, context: @context },
          configuration: configuration
        )

        setup_resource_handlers
      end

      def build_tools
        [
          Tools::ListPromptObjects,
          Tools::SendMessage,
          Tools::GetConversation,
          Tools::GetPendingRequests,
          Tools::RespondToRequest,
          Tools::InspectPO
        ]
      end

      def setup_resource_handlers
        @mcp_server.resources_read_handler do |params|
          handle_resource_read(params)
        end
      end

      def handle_resource_read(params)
        uri = params[:uri]

        case uri
        when %r{^po://([^/]+)/conversation$}
          po_name = ::Regexp.last_match(1)
          read_conversation(po_name)
        when %r{^po://([^/]+)/config$}
          po_name = ::Regexp.last_match(1)
          read_config(po_name)
        when %r{^po://([^/]+)/prompt$}
          po_name = ::Regexp.last_match(1)
          read_prompt(po_name)
        when "bus://messages"
          read_bus_messages
        else
          [{ uri: uri, mimeType: "text/plain", text: "Unknown resource: #{uri}" }]
        end
      end

      def read_conversation(po_name)
        po = @env.registry.get(po_name)
        return [{ uri: "po://#{po_name}/conversation", mimeType: "text/plain", text: "PO not found" }] unless po

        history = po.history.map do |msg|
          { role: msg[:role].to_s, content: msg[:content] }
        end

        [{
          uri: "po://#{po_name}/conversation",
          mimeType: "application/json",
          text: JSON.pretty_generate(history)
        }]
      end

      def read_config(po_name)
        po = @env.registry.get(po_name)
        return [{ uri: "po://#{po_name}/config", mimeType: "text/plain", text: "PO not found" }] unless po

        [{
          uri: "po://#{po_name}/config",
          mimeType: "application/json",
          text: JSON.pretty_generate(po.config)
        }]
      end

      def read_prompt(po_name)
        po = @env.registry.get(po_name)
        return [{ uri: "po://#{po_name}/prompt", mimeType: "text/plain", text: "PO not found" }] unless po

        [{
          uri: "po://#{po_name}/prompt",
          mimeType: "text/markdown",
          text: po.body
        }]
      end

      def read_bus_messages
        entries = @env.bus.recent(50).map do |entry|
          {
            from: entry[:from],
            to: entry[:to],
            message: entry[:message],
            timestamp: entry[:timestamp]&.iso8601
          }
        end

        [{
          uri: "bus://messages",
          mimeType: "application/json",
          text: JSON.pretty_generate(entries)
        }]
      end

      def run_stdio_transport
        transport = ::MCP::Server::Transports::StdioTransport.new(@mcp_server)
        transport.open
      end
    end
  end
end

# Require tools
require_relative "tools/list_prompt_objects"
require_relative "tools/send_message"
require_relative "tools/get_conversation"
require_relative "tools/get_pending_requests"
require_relative "tools/respond_to_request"
require_relative "tools/inspect_po"
