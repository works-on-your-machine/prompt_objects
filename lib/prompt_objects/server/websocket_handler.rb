# frozen_string_literal: true

require "json"
require "async"

module PromptObjects
  module Server
    # Handles WebSocket connections for real-time communication with the frontend.
    # Subscribes to MessageBus for state updates and handles client messages.
    #
    # == Real-time UI Feedback Pattern ==
    #
    # IMPORTANT: All user actions must provide immediate visual feedback BEFORE
    # async operations complete. This makes the UI feel "alive" and responsive.
    #
    # When implementing new features, follow this pattern:
    #
    # 1. SWITCH CONTEXT FIRST
    #    When creating/switching threads, sessions, etc., send the context switch
    #    message FIRST so the frontend displays the new context immediately.
    #    Example: thread_created → frontend switches to new thread
    #
    # 2. UPDATE NAVIGATION
    #    Send updated lists (sessions, threads) immediately so sidebars reflect
    #    the change without waiting for async work to complete.
    #    Example: po_state with sessions list → ThreadsSidebar shows new thread
    #
    # 3. SHOW USER INPUT
    #    Send the user's input back immediately so they see it in the UI.
    #    Don't wait for the AI to respond before showing what the user typed.
    #    Example: session_updated with user message → chat shows "You: ..."
    #
    # 4. SHOW PROGRESS
    #    Update status indicators during work (thinking, calling_tool, etc.).
    #    Use streaming for incremental content when supported.
    #    Example: po_state status "thinking" → spinner/animation shown
    #
    # 5. CONFIRM COMPLETION
    #    Send final authoritative state after async work completes.
    #    Example: session_updated with full messages → final chat state
    #
    # Message flow for "send message with new thread":
    #   thread_created       → switch to new thread
    #   po_state (sessions)  → update sidebar
    #   session_updated      → show user message
    #   po_state (thinking)  → show progress indicator
    #   [stream chunks]      → incremental AI response
    #   po_response          → complete AI response
    #   session_updated      → final messages
    #   po_state (idle)      → clear progress indicator
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
        when "create_thread"
          handle_create_thread(message["payload"])
        when "get_thread_tree"
          handle_get_thread_tree(message["payload"])
        when "get_llm_config"
          handle_get_llm_config
        when "switch_llm"
          handle_switch_llm(message["payload"])
        when "update_prompt"
          handle_update_prompt(message["payload"])
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
        new_thread = payload["new_thread"] # If true, create a new thread first

        po = @runtime.registry.get(po_name)

        unless po.is_a?(PromptObject)
          send_error("Unknown prompt object: #{po_name}")
          return
        end

        # If new_thread requested, create one first
        if new_thread
          thread_id = po.new_thread
          # Notify client of new thread immediately so they see it
          send_message(
            type: "thread_created",
            payload: {
              target: po_name,
              thread_id: thread_id,
              thread_type: "root"
            }
          )
          # Also send updated sessions list so ThreadsSidebar shows it immediately
          send_message(
            type: "po_state",
            payload: {
              name: po_name,
              state: { sessions: po.list_sessions.map { |s| session_summary(s) } }
            }
          )
        end

        # Capture the session_id at request start so response goes to correct session
        request_session_id = po.session_id

        # Update PO state to working AND send the user message for immediate UI feedback
        send_message(
          type: "po_state",
          payload: { name: po_name, state: { status: "thinking" } }
        )

        # Send immediate session update showing the user's message
        # This gives instant feedback before the AI responds
        # Include existing messages so we don't clear the chat when continuing a thread
        existing_messages = session_messages(po, request_session_id)
        new_user_message = { role: "user", content: content, from: "human" }
        send_message(
          type: "session_updated",
          payload: {
            target: po_name,
            session_id: request_session_id,
            messages: existing_messages + [new_user_message]
          }
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

            # Auto-name the thread if it doesn't have a name yet
            auto_name_thread_if_needed(po, request_session_id, content)

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

            # Also send updated sessions list (for thread panel)
            send_message(
              type: "po_state",
              payload: {
                name: po_name,
                state: { sessions: po.list_sessions.map { |s| session_summary(s) } }
              }
            )
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

      # Auto-name a thread based on the user's first message if it doesn't have a name
      def auto_name_thread_if_needed(po, session_id, user_message)
        return unless @runtime.session_store && session_id

        session = @runtime.session_store.get_session(session_id)
        return if session.nil? || session[:name] # Already has a name

        @runtime.session_store.auto_name_thread(session_id, user_message)
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

      def handle_create_thread(payload)
        po_name = payload["target"]
        thread_name = payload["name"]
        thread_type = payload["thread_type"] || "root"

        po = @runtime.registry.get(po_name)
        return send_error("Unknown prompt object: #{po_name}") unless po.is_a?(PromptObject)

        thread_id = po.new_thread(name: thread_name)

        send_message(
          type: "thread_created",
          payload: {
            target: po_name,
            thread_id: thread_id,
            name: thread_name,
            thread_type: thread_type
          }
        )

        # Also send updated PO state
        send_message(
          type: "po_state",
          payload: { name: po_name, state: po_state_hash(po) }
        )
      end

      def handle_get_thread_tree(payload)
        session_id = payload["session_id"]
        return send_error("Session ID required") unless session_id
        return send_error("No session store available") unless @runtime.session_store

        tree = @runtime.session_store.get_thread_tree(session_id)
        return send_error("Session not found: #{session_id}") unless tree

        send_message(
          type: "thread_tree",
          payload: { tree: serialize_thread_tree(tree) }
        )
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

      def handle_update_prompt(payload)
        po_name = payload["target"]
        new_prompt = payload["prompt"]

        po = @runtime.registry.get(po_name)
        return send_error("Unknown prompt object: #{po_name}") unless po.is_a?(PromptObject)

        # Update the body in memory
        po.instance_variable_set(:@body, new_prompt)

        # Persist to file
        if po.save
          # Notify for real-time UI update (broadcasts to all clients)
          @runtime.notify_po_modified(po)

          send_message(
            type: "prompt_updated",
            payload: { target: po_name, success: true }
          )
        else
          send_error("Failed to save prompt for #{po_name}")
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

        messages = @runtime.session_store.get_messages(session_id)
        messages.map { |m| message_to_hash(m) }
      end

      def session_summary(session)
        {
          id: session[:id],
          name: session[:name],
          message_count: session[:message_count] || 0,
          updated_at: session[:updated_at]&.iso8601,
          # Thread fields
          parent_session_id: session[:parent_session_id],
          parent_po: session[:parent_po],
          thread_type: session[:thread_type] || "root"
        }
      end

      # Recursively serialize a thread tree for JSON
      def serialize_thread_tree(tree)
        return nil unless tree

        {
          session: session_summary(tree[:session]),
          children: (tree[:children] || []).map { |child| serialize_thread_tree(child) }
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
              # Handle both ToolCall objects and Hashes
              tc_id = tc.respond_to?(:id) ? tc.id : (tc[:id] || tc["id"])
              tc_name = tc.respond_to?(:name) ? tc.name : (tc[:name] || tc["name"])
              tc_args = tc.respond_to?(:arguments) ? tc.arguments : (tc[:arguments] || tc["arguments"] || {})
              { id: tc_id, name: tc_name, arguments: tc_args }
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
