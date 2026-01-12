# frozen_string_literal: true

require "json"
require "async"

module PromptObjects
  module Server
    # Handles WebSocket connections for real-time communication with the frontend.
    # Subscribes to MessageBus for state updates and handles client messages.
    class WebSocketHandler
      def initialize(runtime:, connection:, app: nil)
        @runtime = runtime
        @connection = connection
        @app = app
        @subscribed = false
        @bus_subscription = nil
      end

      def run
        subscribe_to_bus
        send_initial_state
        read_loop
      ensure
        unsubscribe_from_bus
      end

      # Send a message to this client (public for broadcasting).
      def send_message(data)
        json = JSON.generate(data)
        @connection.write(json)
        @connection.flush
      rescue => e
        puts "WebSocket write error: #{e.message}" if ENV["DEBUG"]
      end

      private

      # === MessageBus Integration ===

      def subscribe_to_bus
        @bus_subscription = ->(entry) { on_bus_message(entry) }
        @runtime.bus.subscribe(&@bus_subscription)

        # Subscribe to HumanQueue for notification events
        @human_queue_subscription = ->(event, request) { on_human_queue_event(event, request) }
        @runtime.human_queue.subscribe(&@human_queue_subscription)

        @subscribed = true
      end

      def unsubscribe_from_bus
        return unless @subscribed

        @runtime.bus.unsubscribe(@bus_subscription) if @bus_subscription
        @runtime.human_queue.unsubscribe(@human_queue_subscription) if @human_queue_subscription

        @subscribed = false
      end

      def on_human_queue_event(event, request)
        case event
        when :added
          send_message(
            type: "notification",
            payload: request_to_hash(request)
          )
        when :resolved
          send_message(
            type: "notification_resolved",
            payload: { id: request.id }
          )
        end
      rescue => e
        puts "WebSocket notification error: #{e.message}" if ENV["DEBUG"]
      end

      def on_bus_message(entry)
        send_message(
          type: "bus_message",
          payload: {
            from: entry[:from],
            to: entry[:to],
            content: entry[:message],
            timestamp: entry[:timestamp].iso8601
          }
        )
      rescue => e
        # Connection may be closed, ignore errors
        puts "WebSocket send error: #{e.message}" if ENV["DEBUG"]
      end

      # === Initial State ===

      def send_initial_state
        # Send environment info
        send_message(
          type: "environment",
          payload: {
            name: @runtime.name,
            path: @runtime.env_path,
            po_count: @runtime.registry.prompt_objects.size,
            primitive_count: @runtime.registry.primitives.size
          }
        )

        # Send LLM config
        handle_get_llm_config

        # Send state of all POs
        # Always send "idle" status for initial state - from this connection's
        # perspective, no work is pending (even if another connection has a request)
        @runtime.registry.prompt_objects.each do |po|
          send_message(
            type: "po_state",
            payload: {
              name: po.name,
              state: po_state_hash(po).merge(status: "idle")
            }
          )
        end

        # Send pending human requests (notifications)
        @runtime.human_queue.all_pending.each do |request|
          send_message(
            type: "notification",
            payload: request_to_hash(request)
          )
        end

        # Send recent bus messages (last 50)
        @runtime.bus.log.last(50).each do |entry|
          send_message(
            type: "bus_message",
            payload: {
              from: entry[:from],
              to: entry[:to],
              content: entry[:message],
              timestamp: entry[:timestamp].iso8601
            }
          )
        end
      end

      # === Client Message Handling ===

      def read_loop
        while (message = @connection.read)
          handle_client_message(message)
        end
      rescue Async::Stop, EOFError, IOError
        # Connection closed, exit gracefully
      rescue => e
        puts "WebSocket error: #{e.message}"
        puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      end

      def handle_client_message(raw_message)
        # raw_message is a Protocol::WebSocket::TextMessage
        data = raw_message.respond_to?(:buffer) ? raw_message.buffer : raw_message.to_s
        message = JSON.parse(data)

        case message["type"]
        when "send_message"
          handle_send_message(message["payload"])
        when "respond_to_notification"
          handle_notification_response(message["payload"])
        when "update_po"
          handle_update_po(message["payload"])
        when "create_session"
          handle_create_session(message["payload"])
        when "switch_session"
          handle_switch_session(message["payload"])
        when "get_llm_config"
          handle_get_llm_config
        when "switch_llm"
          handle_switch_llm(message["payload"])
        when "ping"
          send_message(type: "pong", payload: {})
        else
          send_error("Unknown message type: #{message['type']}")
        end
      rescue JSON::ParserError => e
        send_error("Invalid JSON: #{e.message}")
      rescue => e
        send_error("Error: #{e.message}")
        puts "Handler error: #{e.message}"
        puts e.backtrace.first(5).join("\n") if ENV["DEBUG"]
      end

      def handle_send_message(payload)
        po_name = payload["target"]
        content = payload["content"]

        po = @runtime.registry.get(po_name)

        unless po.is_a?(PromptObject)
          send_error("Unknown prompt object: #{po_name}")
          return
        end

        # Capture the session_id at request start so response goes to correct session
        request_session_id = po.session_id

        # Update PO state to working
        send_message(
          type: "po_state",
          payload: { name: po_name, state: { status: "thinking" } }
        )

        # Run in async context
        Async do
          # Use tui_mode: true so ask_human uses HumanQueue (blocking) instead of REPL mode
          context = @runtime.context(tui_mode: true)
          context.current_capability = "human"

          begin
            # TODO: Add streaming support to receive()
            # For now, just get the full response
            response = po.receive(content, context: context)

            # Send the complete response with session_id for correct routing
            send_message(
              type: "po_response",
              payload: {
                target: po_name,
                session_id: request_session_id,
                content: response
              }
            )

            # Send session update for the session where messages were added
            # This ensures the correct session is updated even if user switched
            if request_session_id
              send_message(
                type: "session_updated",
                payload: {
                  target: po_name,
                  session_id: request_session_id,
                  messages: session_messages(po, request_session_id)
                }
              )
            end
          rescue => e
            send_error("Error from #{po_name}: #{e.message}")
          ensure
            # Update PO state back to idle (status only, not session data)
            send_message(
              type: "po_state",
              payload: { name: po_name, state: { status: "idle" } }
            )
          end
        end
      end

      def handle_notification_response(payload)
        request_id = payload["id"]
        response = payload["response"]

        @runtime.human_queue.respond(request_id, response)

        send_message(
          type: "notification_resolved",
          payload: { id: request_id }
        )
      end

      def handle_update_po(payload)
        po_name = payload["name"]
        updates = payload["updates"]

        po = @runtime.registry.get(po_name)
        return send_error("Unknown prompt object: #{po_name}") unless po.is_a?(PromptObject)

        # TODO: Implement PO updates (capabilities, etc.)
        send_message(
          type: "po_updated",
          payload: { name: po_name }
        )
      end

      def handle_create_session(payload)
        po_name = payload["target"]
        session_name = payload["name"]

        po = @runtime.registry.get(po_name)
        return send_error("Unknown prompt object: #{po_name}") unless po.is_a?(PromptObject)

        session_id = po.new_session(name: session_name)

        send_message(
          type: "session_created",
          payload: {
            target: po_name,
            session_id: session_id,
            name: session_name
          }
        )

        # Also send updated PO state
        send_message(
          type: "po_state",
          payload: { name: po_name, state: po_state_hash(po) }
        )
      end

      def handle_switch_session(payload)
        po_name = payload["target"]
        session_id = payload["session_id"]

        po = @runtime.registry.get(po_name)
        return send_error("Unknown prompt object: #{po_name}") unless po.is_a?(PromptObject)

        if po.switch_session(session_id)
          send_message(
            type: "session_switched",
            payload: { target: po_name, session_id: session_id }
          )

          # Send updated PO state with new session's messages
          send_message(
            type: "po_state",
            payload: { name: po_name, state: po_state_hash(po) }
          )
        else
          send_error("Could not switch to session: #{session_id}")
        end
      end

      def handle_get_llm_config
        config = @runtime.llm_config

        # Get models for each provider
        providers_info = LLM::Factory.providers.map do |provider|
          info = LLM::Factory.provider_info(provider)
          {
            name: provider,
            models: info[:models],
            default_model: info[:default_model],
            available: LLM::Factory.available_providers[provider]
          }
        end

        send_message(
          type: "llm_config",
          payload: {
            current_provider: config[:provider],
            current_model: config[:model],
            providers: providers_info
          }
        )
      end

      def handle_switch_llm(payload)
        provider = payload["provider"]
        model = payload["model"]

        begin
          result = @runtime.switch_llm(provider: provider, model: model)

          send_message(
            type: "llm_switched",
            payload: {
              provider: result[:provider],
              model: result[:model]
            }
          )

          # Broadcast to all connected clients via app
          @app&.broadcast(
            type: "llm_switched",
            payload: {
              provider: result[:provider],
              model: result[:model]
            }
          )
        rescue PromptObjects::Error => e
          send_error("Failed to switch LLM: #{e.message}")
        end
      end

      # === Helpers ===

      def send_error(message)
        send_message(type: "error", payload: { message: message })
      end

      def po_state_hash(po)
        {
          status: po.instance_variable_get(:@state) || "idle",
          description: po.description,
          capabilities: po.config["capabilities"] || [],
          current_session: current_session_hash(po),
          sessions: po.list_sessions.map { |s| session_summary(s) },
          # Include full prompt for inspection
          prompt: po.body,
          config: po.config
        }
      end

      def current_session_hash(po)
        return nil unless po.session_id

        {
          id: po.session_id,
          messages: po.history.map { |m| message_to_hash(m) }
        }
      end

      # Get messages for a specific session (may not be current session)
      def session_messages(po, session_id)
        return [] unless @runtime.session_store

        messages = @runtime.session_store.get_messages(session_id: session_id)
        messages.map { |m| message_to_hash(m) }
      end

      def session_summary(session)
        {
          id: session[:id],
          name: session[:name],
          message_count: session[:message_count] || 0,
          updated_at: session[:updated_at]&.iso8601
        }
      end

      def message_to_hash(msg)
        case msg[:role]
        when :user
          { role: "user", content: msg[:content], from: msg[:from] }
        when :assistant
          hash = { role: "assistant", content: msg[:content] }
          if msg[:tool_calls]
            hash[:tool_calls] = msg[:tool_calls].map do |tc|
              { id: tc.id, name: tc.name, arguments: tc.arguments }
            end
          end
          hash
        when :tool
          { role: "tool", results: msg[:results] }
        else
          { role: msg[:role].to_s, content: msg[:content] }
        end
      end

      def request_to_hash(request)
        {
          id: request.id,
          po_name: request.capability,  # capability is the PO name
          type: "ask_human",            # hardcode type since it's always ask_human
          message: request.question,    # question is the message
          options: request.options || []
        }
      end
    end
  end
end
