# frozen_string_literal: true

require "json"
require "rack"

module PromptObjects
  module Server
    module API
      # REST API routes for the PromptObjects server.
      # Provides endpoints for listing POs, sessions, and environment info.
      class Routes
        def initialize(runtime)
          @runtime = runtime
        end

        def call(env)
          request = Rack::Request.new(env)
          path = request.path_info.sub("/api", "")

          response = route(request, path)
          json_response(response)
        rescue => e
          json_response({ error: e.message }, status: 500)
        end

        private

        def route(request, path)
          method = request.request_method

          case [method, path]

          # Environment
          when ["GET", "/environment"]
            get_environment

          # Prompt Objects
          when ["GET", "/prompt_objects"]
            list_prompt_objects

          when ["GET", %r{^/prompt_objects/([^/]+)$}]
            get_prompt_object(path_param(path, 1))

          when ["POST", "/prompt_objects"]
            create_prompt_object(request.body.read)

          # Sessions
          when ["GET", %r{^/prompt_objects/([^/]+)/sessions$}]
            list_sessions(path_param(path, 1))

          when ["GET", %r{^/prompt_objects/([^/]+)/sessions/([^/]+)$}]
            get_session(path_param(path, 1), path_param(path, 2))

          when ["POST", %r{^/prompt_objects/([^/]+)/sessions$}]
            create_session(path_param(path, 1), request.body.read)

          # Primitives
          when ["GET", "/primitives"]
            list_primitives

          # Message Bus
          when ["GET", "/bus/recent"]
            get_recent_bus_messages

          else
            { error: "Not found", path: path }
          end
        end

        # === Environment ===

        def get_environment
          manifest_data = if @runtime.manifest
            {
              name: @runtime.manifest.name,
              description: @runtime.manifest.description,
              icon: @runtime.manifest.icon,
              created_at: @runtime.manifest.created_at&.iso8601,
              last_opened: @runtime.manifest.last_opened&.iso8601
            }
          end

          {
            name: @runtime.name,
            path: @runtime.env_path,
            prompt_object_count: @runtime.registry.prompt_objects.size,
            primitive_count: @runtime.registry.primitives.size,
            manifest: manifest_data
          }
        end

        # === Prompt Objects ===

        def list_prompt_objects
          pos = @runtime.registry.prompt_objects.map do |po|
            po_summary(po)
          end

          { prompt_objects: pos }
        end

        def get_prompt_object(name)
          po = @runtime.registry.get(name)

          unless po.is_a?(PromptObject)
            return { error: "Not found", name: name }
          end

          po_full(po)
        end

        def create_prompt_object(body)
          # TODO: Implement PO creation via API
          { error: "Not implemented" }
        end

        # === Sessions ===

        def list_sessions(po_name)
          po = @runtime.registry.get(po_name)

          unless po.is_a?(PromptObject)
            return { error: "Not found", name: po_name }
          end

          sessions = po.list_sessions.map do |s|
            {
              id: s[:id],
              name: s[:name],
              message_count: s[:message_count] || 0,
              created_at: s[:created_at]&.iso8601,
              updated_at: s[:updated_at]&.iso8601
            }
          end

          { sessions: sessions }
        end

        def get_session(po_name, session_id)
          po = @runtime.registry.get(po_name)

          unless po.is_a?(PromptObject)
            return { error: "Prompt object not found", name: po_name }
          end

          return { error: "No session store" } unless @runtime.session_store

          session = @runtime.session_store.get_session(session_id)

          unless session && session[:po_name] == po_name
            return { error: "Session not found", id: session_id }
          end

          messages = @runtime.session_store.get_messages(session_id)

          {
            id: session[:id],
            name: session[:name],
            po_name: session[:po_name],
            messages: messages.map { |m| format_message(m) },
            created_at: session[:created_at]&.iso8601,
            updated_at: session[:updated_at]&.iso8601
          }
        end

        def create_session(po_name, body)
          po = @runtime.registry.get(po_name)

          unless po.is_a?(PromptObject)
            return { error: "Not found", name: po_name }
          end

          params = body.empty? ? {} : JSON.parse(body)
          session_name = params["name"]

          session_id = po.new_session(name: session_name)

          {
            success: true,
            session_id: session_id,
            name: session_name
          }
        end

        # === Primitives ===

        def list_primitives
          primitives = @runtime.registry.primitives.map do |p|
            {
              name: p.name,
              description: p.description
            }
          end

          { primitives: primitives }
        end

        # === Message Bus ===

        def get_recent_bus_messages
          entries = @runtime.bus.recent(50)

          messages = entries.map do |e|
            {
              from: e[:from],
              to: e[:to],
              summary: e[:summary],
              content: serialize_bus_content(e[:message]),
              timestamp: e[:timestamp].iso8601
            }
          end

          { messages: messages }
        end

        def serialize_bus_content(message)
          case message
          when Hash then message
          when String then message
          else message.to_s
          end
        end

        # === Helpers ===

        def po_summary(po)
          {
            name: po.name,
            description: po.description,
            capabilities: po.config["capabilities"] || [],
            session_count: po.list_sessions.size
          }
        end

        def po_full(po)
          {
            name: po.name,
            description: po.description,
            capabilities: po.config["capabilities"] || [],
            body: po.body,
            config: po.config,
            sessions: po.list_sessions.map do |s|
              {
                id: s[:id],
                name: s[:name],
                message_count: s[:message_count] || 0
              }
            end,
            current_session: po.session_id,
            history: po.history.map { |m| format_history_message(m) }
          }
        end

        def format_message(msg)
          {
            role: msg[:role].to_s,
            content: msg[:content],
            from_po: msg[:from_po],
            tool_calls: msg[:tool_calls],
            tool_results: msg[:tool_results],
            created_at: msg[:created_at]&.iso8601
          }.compact
        end

        def format_history_message(msg)
          case msg[:role]
          when :user
            { role: "user", content: msg[:content], from: msg[:from] }
          when :assistant
            h = { role: "assistant", content: msg[:content] }
            if msg[:tool_calls]
              h[:tool_calls] = msg[:tool_calls].map do |tc|
                { id: tc.id, name: tc.name, arguments: tc.arguments }
              end
            end
            h
          when :tool
            { role: "tool", results: msg[:results] }
          else
            { role: msg[:role].to_s, content: msg[:content] }
          end
        end

        def path_param(path, index)
          # Extract path parameter from regex match
          # /prompt_objects/foo -> foo (index 1)
          # /prompt_objects/foo/sessions/bar -> foo (1), bar (2)
          parts = path.split("/").reject(&:empty?)
          parts[index]
        end

        def json_response(data, status: 200)
          body = JSON.generate(data)
          [
            status,
            {
              "content-type" => "application/json",
              "access-control-allow-origin" => "*"
            },
            [body]
          ]
        end
      end
    end
  end
end
