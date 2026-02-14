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

          case method
          when "GET"
            route_get(request, path)
          when "POST"
            route_post(request, path)
          else
            { error: "Not found", path: path }
          end
        end

        def route_get(_request, path)
          case path
          when "/environment"
            get_environment
          when "/prompt_objects"
            list_prompt_objects
          when "/primitives"
            list_primitives
          when "/bus/recent"
            get_recent_bus_messages
          when "/events"
            get_recent_events(_request)
          when %r{^/prompt_objects/([^/]+)/sessions/([^/]+)$}
            get_session($1, $2)
          when %r{^/prompt_objects/([^/]+)/sessions$}
            list_sessions($1)
          when %r{^/prompt_objects/([^/]+)$}
            get_prompt_object($1)
          when %r{^/events/session/([^/]+)$}
            get_session_events($1)
          when %r{^/sessions/([^/]+)/usage$}
            get_session_usage($1, _request)
          when %r{^/sessions/([^/]+)/export$}
            export_thread($1, _request)
          else
            { error: "Not found", path: path }
          end
        end

        def route_post(request, path)
          case path
          when "/prompt_objects"
            create_prompt_object(request.body.read)
          when %r{^/prompt_objects/([^/]+)/message$}
            send_message($1, request.body.read)
          when %r{^/prompt_objects/([^/]+)/sessions$}
            create_session($1, request.body.read)
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

        # === Messages ===

        def send_message(po_name, body)
          po = @runtime.registry.get(po_name)

          unless po.is_a?(PromptObject)
            return { error: "Prompt object not found", name: po_name }
          end

          params = JSON.parse(body)
          message = params["message"]
          session_id = params["session_id"]
          new_thread = params["new_thread"]

          return { error: "Message is required" } unless message && !message.empty?

          # Create a new thread if requested
          if new_thread
            session_id = po.new_thread
          end

          # Switch to specified session if provided
          if session_id && session_id != po.session_id
            po.switch_session(session_id)
          end

          request_session_id = po.session_id

          # Send the message through the same path as WebSocket
          context = @runtime.context(tui_mode: false)
          context.current_capability = "human"

          # Log to bus
          @runtime.bus.publish(from: "human", to: po.name, message: message, session_id: request_session_id)

          response = po.receive(message, context: context)

          # Log response to bus
          @runtime.bus.publish(from: po.name, to: "human", message: response, session_id: request_session_id)

          # Count events for this session
          event_count = if @runtime.session_store
            @runtime.session_store.get_events(session_id: request_session_id).length
          end

          {
            response: response,
            po_name: po.name,
            session_id: request_session_id,
            event_count: event_count
          }
        rescue JSON::ParserError
          { error: "Invalid JSON body" }
        end

        # === Sessions ===

        def list_sessions(po_name)
          po = @runtime.registry.get(po_name)

          unless po.is_a?(PromptObject)
            return { error: "Not found", name: po_name }
          end

          sessions = po.list_sessions.map do |s|
            PromptObject.serialize_session(s)
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

        # === Events ===

        def get_recent_events(request)
          return { error: "No session store" } unless @runtime.session_store

          count = (request.params["count"] || 50).to_i
          events = @runtime.session_store.get_recent_events(count)

          { events: events.map { |e| format_event(e) } }
        end

        def get_session_events(session_id)
          return { error: "No session store" } unless @runtime.session_store

          events = @runtime.session_store.get_events(session_id: session_id)

          { events: events.map { |e| format_event(e) } }
        end

        def format_event(event)
          {
            id: event[:id],
            session_id: event[:session_id],
            from: event[:from],
            to: event[:to],
            summary: event[:summary],
            message: event[:message],
            timestamp: event[:timestamp]&.iso8601
          }
        end

        # === Usage ===

        def get_session_usage(session_id, request)
          return { error: "No session store" } unless @runtime.session_store

          include_tree = request.params["tree"] == "true"

          usage = if include_tree
                    @runtime.session_store.thread_tree_usage(session_id)
                  else
                    @runtime.session_store.session_usage(session_id)
                  end

          by_model = {}
          usage[:by_model].each { |model, data| by_model[model.to_s] = data }

          {
            session_id: session_id,
            include_tree: include_tree,
            input_tokens: usage[:input_tokens],
            output_tokens: usage[:output_tokens],
            total_tokens: usage[:total_tokens],
            estimated_cost_usd: usage[:estimated_cost_usd].round(6),
            calls: usage[:calls],
            by_model: by_model
          }
        end

        # === Export ===

        def export_thread(session_id, request)
          return { error: "No session store" } unless @runtime.session_store

          format = request.params["format"] || "markdown"

          case format
          when "markdown"
            content = @runtime.session_store.export_thread_tree_markdown(session_id)
            return { error: "Session not found" } unless content
            { format: "markdown", content: content }
          when "json"
            data = @runtime.session_store.export_thread_tree_json(session_id)
            return { error: "Session not found" } unless data
            data
          else
            { error: "Unknown format: #{format}" }
          end
        end

        # === Helpers ===

        def po_summary(po)
          po.to_summary_hash(registry: @runtime.registry)
        end

        def po_full(po)
          po.to_inspect_hash(registry: @runtime.registry)
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
