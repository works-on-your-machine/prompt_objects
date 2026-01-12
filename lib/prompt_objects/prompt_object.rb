# frozen_string_literal: true

module PromptObjects
  # A Prompt Object is a capability backed by an LLM.
  # It interprets messages semantically using its markdown "soul" as the system prompt.
  class PromptObject < Capability
    attr_reader :config, :body, :history, :session_id

    # @param config [Hash] Parsed frontmatter (name, description, capabilities)
    # @param body [String] Markdown body (the "soul" - becomes system prompt)
    # @param env [Environment] Reference to the environment
    # @param llm [LLM::OpenAIAdapter] LLM adapter for making calls
    def initialize(config:, body:, env:, llm:)
      super()
      @config = config
      @body = body
      @env = env
      @llm = llm
      @history = []
      @session_id = nil

      # Load existing session if session store is available
      load_or_create_session if session_store
    end

    # Get the session store from the environment.
    # @return [Session::Store, nil]
    def session_store
      @env.session_store
    end

    def name
      @config["name"] || "unnamed"
    end

    def description
      @config["description"] || "A prompt object"
    end

    # Prompt objects accept natural language messages.
    def parameters
      {
        type: "object",
        properties: {
          message: {
            type: "string",
            description: "Natural language message to send"
          }
        },
        required: ["message"]
      }
    end

    # Handle an incoming message by running the LLM conversation loop.
    # @param message [String, Hash] The incoming message
    # @param context [Hash] Execution context
    # @return [String] The response
    def receive(message, context:)
      # Normalize message to string
      content = normalize_message(message)

      # Track who sent this message - another PO or a human?
      sender = context.current_capability
      from = (sender && sender != name) ? sender : "human"

      user_msg = { role: :user, content: content, from: from }
      @history << user_msg
      persist_message(user_msg)
      @state = :working

      # Conversation loop - keep going until LLM responds without tool calls
      loop do
        response = @llm.chat(
          system: build_system_prompt,
          messages: @history,
          tools: available_tool_descriptors
        )

        if response.tool_calls?
          # Execute tools and continue the loop
          results = execute_tool_calls(response.tool_calls, context)
          assistant_msg = {
            role: :assistant,
            # Don't include content when there are tool calls - force LLM to
            # wait for tool results before generating a response. This prevents
            # the model from "hedging" by generating both a response AND a tool call.
            content: nil,
            tool_calls: response.tool_calls
          }
          @history << assistant_msg
          persist_message(assistant_msg)

          tool_msg = { role: :tool, results: results }
          @history << tool_msg
          persist_message(tool_msg)
        else
          # No tool calls - we have our final response
          assistant_msg = { role: :assistant, content: response.content }
          @history << assistant_msg
          persist_message(assistant_msg)
          @state = :idle
          return response.content
        end
      end
    end

    # --- Session Management ---

    # List all sessions for this PO.
    # @return [Array<Hash>] Session data
    def list_sessions
      return [] unless session_store

      session_store.list_sessions(po_name: name)
    end

    # Switch to a different session.
    # @param session_id [String] Session ID to switch to
    # @return [Boolean] True if switch was successful
    def switch_session(session_id)
      return false unless session_store

      session = session_store.get_session(session_id)
      return false unless session && session[:po_name] == name

      @session_id = session_id
      reload_history_from_session
      true
    end

    # Create a new session and switch to it.
    # @param name [String, nil] Optional session name
    # @return [String] New session ID
    def new_session(name: nil)
      return nil unless session_store

      @session_id = session_store.create_session(po_name: self.name, name: name)
      @history = []
      @session_id
    end

    # Clear the current session's history.
    def clear_history
      @history = []
      session_store&.clear_messages(@session_id) if @session_id
    end

    private

    def normalize_message(message)
      case message
      when String
        message
      when Hash
        message[:message] || message["message"] || message.to_s
      else
        message.to_s
      end
    end

    def available_tool_descriptors
      # Get declared capabilities from config
      declared = @config["capabilities"] || []

      # Add universal capabilities (available to all POs)
      all_caps = declared + UNIVERSAL_CAPABILITIES

      all_caps.filter_map do |cap_name|
        cap = @env.registry&.get(cap_name)
        cap&.descriptor
      end
    end

    def build_system_prompt
      # Build context about this PO's identity
      declared_caps = @config["capabilities"] || []
      all_caps = declared_caps + UNIVERSAL_CAPABILITIES

      context_block = <<~CONTEXT
        ## System Context

        You are a prompt object named "#{name}".
        When using tools that target a PO (like add_capability), you can use "self" or "#{name}" to target yourself.

        Your declared capabilities: #{declared_caps.empty? ? '(none)' : declared_caps.join(', ')}
        Universal capabilities (always available): #{UNIVERSAL_CAPABILITIES.join(', ')}
      CONTEXT

      "#{@body}\n\n#{context_block}"
    end

    def execute_tool_calls(tool_calls, context)
      # Track the caller for nested calls
      previous_capability = context.current_capability
      previous_calling_po = context.calling_po

      tool_calls.map do |tc|
        capability = @env.registry&.get(tc.name)

        if capability
          # Log the outgoing message
          @env.bus.publish(from: name, to: tc.name, message: tc.arguments)

          # Set context for the tool call
          # calling_po tracks which PO is making the call (for "self" resolution)
          context.calling_po = name
          context.current_capability = tc.name

          result = capability.receive(tc.arguments, context: context)

          # Restore context
          context.current_capability = previous_capability
          context.calling_po = previous_calling_po

          # Log the response
          @env.bus.publish(from: tc.name, to: name, message: result)

          { tool_call_id: tc.id, name: tc.name, content: result }
        else
          { tool_call_id: tc.id, name: tc.name, content: "Unknown capability: #{tc.name}" }
        end
      end
    end

    # --- Session Persistence Helpers ---

    # Load existing session or create a new one.
    def load_or_create_session
      session = session_store.get_or_create_session(po_name: name)
      @session_id = session[:id]
      reload_history_from_session
    end

    # Reload history from the current session.
    def reload_history_from_session
      return unless session_store && @session_id

      messages = session_store.get_messages(@session_id)
      @history = messages.map { |msg| convert_db_message_to_history(msg) }
    end

    # Persist a message to the session store.
    def persist_message(msg)
      return unless session_store && @session_id

      case msg[:role]
      when :user
        session_store.add_message(
          session_id: @session_id,
          role: :user,
          content: msg[:content],
          from_po: msg[:from]
        )
      when :assistant
        # Serialize tool_calls if present
        tool_calls_data = msg[:tool_calls]&.map do |tc|
          { id: tc.id, name: tc.name, arguments: tc.arguments }
        end

        session_store.add_message(
          session_id: @session_id,
          role: :assistant,
          content: msg[:content],
          tool_calls: tool_calls_data
        )
      when :tool
        session_store.add_message(
          session_id: @session_id,
          role: :tool,
          tool_results: msg[:results]
        )
      end
    end

    # Convert a database message row to history format.
    def convert_db_message_to_history(db_msg)
      case db_msg[:role]
      when :user
        { role: :user, content: db_msg[:content], from: db_msg[:from_po] || "human" }
      when :assistant
        msg = { role: :assistant, content: db_msg[:content] }
        if db_msg[:tool_calls]
          # Reconstruct tool call objects from Hashes
          msg[:tool_calls] = db_msg[:tool_calls].map do |tc|
            LLM::ToolCall.from_hash(tc)
          end
        end
        msg
      when :tool
        { role: :tool, results: db_msg[:tool_results] || [] }
      else
        { role: db_msg[:role], content: db_msg[:content] }
      end
    end
  end
end
