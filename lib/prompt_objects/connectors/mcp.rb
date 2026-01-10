# frozen_string_literal: true

require "mcp"
require_relative "base"

module PromptObjects
  module Connectors
    # MCP (Model Context Protocol) connector for exposing environments to
    # Claude Desktop, Cursor, and other MCP clients.
    class MCP < Base
      attr_reader :mcp_server

      def source_name
        "mcp"
      end

      def start
        @running = true
        setup_mcp_server
        run_stdio_transport
      end

      def stop
        @running = false
        # MCP stdio transport doesn't have a clean shutdown, process exit handles it
      end

      private

      def setup_mcp_server
        @mcp_server = ::MCP::Server.new(
          name: "prompt_objects",
          version: "0.1.0",
          tools: build_tools,
          server_context: {
            env: @runtime,
            context: @runtime.context(tui_mode: true),
            connector: self
          }
        )

        setup_resource_handlers
      end

      def build_tools
        [
          Tools::ListPromptObjects,
          Tools::SendMessage,
          Tools::GetConversation,
          Tools::ListSessions,
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
        when %r{^sessions://([^/]+)$}
          po_name = ::Regexp.last_match(1)
          read_sessions(po_name)
        when "sessions://all"
          read_all_sessions
        else
          [{ uri: uri, mimeType: "text/plain", text: "Unknown resource: #{uri}" }]
        end
      end

      def read_conversation(po_name)
        po = @runtime.registry.get(po_name)
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
        po = @runtime.registry.get(po_name)
        return [{ uri: "po://#{po_name}/config", mimeType: "text/plain", text: "PO not found" }] unless po

        [{
          uri: "po://#{po_name}/config",
          mimeType: "application/json",
          text: JSON.pretty_generate(po.config)
        }]
      end

      def read_prompt(po_name)
        po = @runtime.registry.get(po_name)
        return [{ uri: "po://#{po_name}/prompt", mimeType: "text/plain", text: "PO not found" }] unless po

        [{
          uri: "po://#{po_name}/prompt",
          mimeType: "text/markdown",
          text: po.body
        }]
      end

      def read_bus_messages
        entries = @runtime.bus.recent(50).map do |entry|
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

      def read_sessions(po_name)
        return [{ uri: "sessions://#{po_name}", mimeType: "text/plain", text: "Sessions not available" }] unless @runtime.session_store

        sessions = @runtime.session_store.list_sessions(po_name: po_name)
        [{
          uri: "sessions://#{po_name}",
          mimeType: "application/json",
          text: JSON.pretty_generate(sessions)
        }]
      end

      def read_all_sessions
        return [{ uri: "sessions://all", mimeType: "text/plain", text: "Sessions not available" }] unless @runtime.session_store

        sessions = @runtime.session_store.list_all_sessions
        [{
          uri: "sessions://all",
          mimeType: "application/json",
          text: JSON.pretty_generate(sessions)
        }]
      end

      def run_stdio_transport
        transport = ::MCP::Server::Transports::StdioTransport.new(@mcp_server)
        transport.open
      end

      # MCP Tools
      module Tools
        # List all prompt objects in the environment
        class ListPromptObjects < ::MCP::Tool
          tool_name "list_prompt_objects"
          description "List all available prompt objects in the environment"

          input_schema(
            type: "object",
            properties: {},
            required: []
          )

          def self.call(server_context:)
            env = server_context[:env]

            pos = env.registry.prompt_objects.map do |po|
              {
                name: po.name,
                description: po.description,
                state: po.state.to_s,
                capabilities: po.config["capabilities"] || []
              }
            end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ prompt_objects: pos })
            }])
          end
        end

        # Send a message to a prompt object
        class SendMessage < ::MCP::Tool
          tool_name "send_message"
          description "Send a message to a prompt object. The PO will process it (potentially calling tools) and return a response."

          input_schema(
            type: "object",
            properties: {
              po_name: {
                type: "string",
                description: "Name of the prompt object to message"
              },
              message: {
                type: "string",
                description: "The message to send"
              },
              session_id: {
                type: "string",
                description: "Optional session ID to continue. If not provided, uses or creates a default session."
              }
            },
            required: %w[po_name message]
          )

          def self.call(po_name:, message:, session_id: nil, server_context:)
            env = server_context[:env]
            context = server_context[:context]
            connector = server_context[:connector]

            po = env.registry.get(po_name)
            unless po.is_a?(PromptObjects::PromptObject)
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
              }])
            end

            # Handle session
            current_session_id = setup_session(po, session_id, env, connector)

            # Log to message bus
            env.bus.publish(from: "mcp_client", to: po_name, message: message)

            # Set context for this interaction
            context.current_capability = po_name
            po.state = :working

            begin
              response = po.receive(message, context: context)
              po.state = :idle

              # Update session source
              connector&.send(:update_session_source, current_session_id) if current_session_id

              # Log response
              env.bus.publish(from: po_name, to: "mcp_client", message: response)

              ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({
                  po_name: po_name,
                  response: response,
                  session_id: current_session_id,
                  history_length: po.history.length
                })
              }])
            rescue StandardError => e
              po.state = :idle
              ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: e.message, backtrace: e.backtrace.first(5) })
              }])
            end
          end

          def self.setup_session(po, session_id, env, connector)
            return nil unless env.session_store

            if session_id
              # Switch to specified session
              session = env.session_store.get_session(session_id)
              if session && session[:po_name] == po.name
                po.switch_session(session_id)
                return session_id
              end
            end

            # Use existing session or create new one
            existing_id = po.instance_variable_get(:@session_id)
            return existing_id if existing_id

            # Create new MCP session
            new_id = env.session_store.create_session(
              po_name: po.name,
              name: "MCP Session #{Time.now.strftime('%H:%M')}",
              source: connector&.source_name || "mcp"
            )
            po.instance_variable_set(:@session_id, new_id)
            po.send(:reload_history_from_session) if po.respond_to?(:reload_history_from_session, true)
            new_id
          end
        end

        # Get conversation history for a PO
        class GetConversation < ::MCP::Tool
          tool_name "get_conversation"
          description "Get the conversation history for a prompt object"

          input_schema(
            type: "object",
            properties: {
              po_name: {
                type: "string",
                description: "Name of the prompt object"
              },
              session_id: {
                type: "string",
                description: "Optional session ID. If not provided, returns current session."
              }
            },
            required: %w[po_name]
          )

          def self.call(po_name:, session_id: nil, server_context:)
            env = server_context[:env]

            po = env.registry.get(po_name)
            unless po.is_a?(PromptObjects::PromptObject)
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
              }])
            end

            history = if session_id && env.session_store
                        messages = env.session_store.get_messages(session_id)
                        messages.map { |m| { role: m[:role], content: m[:content] } }
                      else
                        po.history.map { |msg| { role: msg[:role].to_s, content: msg[:content] } }
                      end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({
                po_name: po_name,
                session_id: session_id || po.instance_variable_get(:@session_id),
                history: history
              })
            }])
          end
        end

        # List sessions for a PO or all sessions
        class ListSessions < ::MCP::Tool
          tool_name "list_sessions"
          description "List sessions. Optionally filter by PO name or source."

          input_schema(
            type: "object",
            properties: {
              po_name: {
                type: "string",
                description: "Filter by prompt object name (optional)"
              },
              source: {
                type: "string",
                description: "Filter by source: tui, mcp, api, web (optional)"
              }
            },
            required: []
          )

          def self.call(po_name: nil, source: nil, server_context:)
            env = server_context[:env]

            unless env.session_store
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: "Sessions not available in this environment" })
              }])
            end

            sessions = if po_name
                         env.session_store.list_sessions(po_name: po_name)
                       else
                         env.session_store.list_all_sessions(source: source)
                       end

            sessions_data = sessions.map do |s|
              {
                id: s[:id],
                po_name: s[:po_name],
                name: s[:name],
                source: s[:source],
                message_count: env.session_store.message_count(s[:id]),
                created_at: s[:created_at]&.iso8601,
                updated_at: s[:updated_at]&.iso8601
              }
            end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ sessions: sessions_data })
            }])
          end
        end

        # Get pending human requests
        class GetPendingRequests < ::MCP::Tool
          tool_name "get_pending_requests"
          description "Get all pending human requests across all prompt objects"

          input_schema(
            type: "object",
            properties: {},
            required: []
          )

          def self.call(server_context:)
            env = server_context[:env]

            requests = env.human_queue.pending.map do |req|
              {
                id: req[:id],
                from: req[:from],
                question: req[:question],
                timestamp: req[:timestamp]&.iso8601
              }
            end

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ pending_requests: requests })
            }])
          end
        end

        # Respond to a human request
        class RespondToRequest < ::MCP::Tool
          tool_name "respond_to_request"
          description "Respond to a pending human request"

          input_schema(
            type: "object",
            properties: {
              request_id: {
                type: "string",
                description: "ID of the request to respond to"
              },
              response: {
                type: "string",
                description: "The response to provide"
              }
            },
            required: %w[request_id response]
          )

          def self.call(request_id:, response:, server_context:)
            env = server_context[:env]

            success = env.human_queue.respond(request_id, response)

            if success
              ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ success: true, request_id: request_id })
              }])
            else
              ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: "Request not found or already responded", request_id: request_id })
              }])
            end
          end
        end

        # Inspect a prompt object's details
        class InspectPO < ::MCP::Tool
          tool_name "inspect_po"
          description "Get detailed information about a prompt object including its prompt and capabilities"

          input_schema(
            type: "object",
            properties: {
              po_name: {
                type: "string",
                description: "Name of the prompt object to inspect"
              }
            },
            required: %w[po_name]
          )

          def self.call(po_name:, server_context:)
            env = server_context[:env]

            po = env.registry.get(po_name)
            unless po.is_a?(PromptObjects::PromptObject)
              return ::MCP::Tool::Response.new([{
                type: "text",
                text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
              }])
            end

            info = {
              name: po.name,
              description: po.description,
              state: po.state.to_s,
              prompt: po.body,
              capabilities: po.config["capabilities"] || [],
              config: po.config,
              session_id: po.instance_variable_get(:@session_id),
              history_length: po.history.length
            }

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate(info)
            }])
          end
        end
      end
    end
  end
end
