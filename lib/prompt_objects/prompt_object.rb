# frozen_string_literal: true

module PromptObjects
  # A Prompt Object is a capability backed by an LLM.
  # It interprets messages semantically using its markdown "soul" as the system prompt.
  class PromptObject < Capability
    attr_reader :config, :body, :history, :session_id, :path
    attr_accessor :on_history_updated  # Callback for real-time updates during receive loop

    # @param config [Hash] Parsed frontmatter (name, description, capabilities)
    # @param body [String] Markdown body (the "soul" - becomes system prompt)
    # @param env [Environment] Reference to the environment
    # @param llm [LLM::OpenAIAdapter] LLM adapter for making calls
    # @param path [String, nil] Path to the source .md file (for persistence)
    def initialize(config:, body:, env:, llm:, path: nil)
      super()
      @config = config
      @body = body
      @env = env
      @llm = llm
      @path = path
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
      sender = context.calling_po
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
            tool_calls: response.tool_calls,
            usage: response.usage
          }
          @history << assistant_msg
          persist_message(assistant_msg)

          tool_msg = { role: :tool, results: results }
          @history << tool_msg
          persist_message(tool_msg)

          # Notify callback for real-time UI updates (tool calls as they happen)
          notify_history_updated
        else
          # No tool calls - we have our final response
          assistant_msg = { role: :assistant, content: response.content, usage: response.usage }
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

    # --- File Persistence ---

    # Save the current config and body back to the source file.
    # This persists any runtime changes (like added capabilities) to disk.
    # @return [Boolean] True if saved successfully, false if no path or error
    def save
      return false unless @path

      # Build YAML frontmatter with proper formatting
      yaml_content = @config.to_yaml

      # Combine frontmatter and body
      content = "#{yaml_content}---\n\n#{@body}\n"

      File.write(@path, content, encoding: "UTF-8")
      true
    rescue => e
      puts "Error saving PO #{name} to #{@path}: #{e.message}" if ENV["DEBUG"]
      false
    end

    # --- Thread/Delegation Support ---

    # Create a delegation thread for handling a call from another PO.
    # @param parent_po [String] Name of the PO that initiated the call
    # @param parent_session_id [String] Session ID in the parent PO
    # @param parent_message_id [Integer, nil] Message ID that triggered the delegation
    # @return [String, nil] New thread ID or nil if no session store
    def create_delegation_thread(parent_po:, parent_session_id:, parent_message_id: nil)
      return nil unless session_store

      session_store.create_thread(
        po_name: name,
        parent_po: parent_po,
        parent_session_id: parent_session_id,
        parent_message_id: parent_message_id,
        thread_type: "delegation",
        source: "delegation"
      )
    end

    # Execute a message in a specific thread, then restore the original session.
    # @param message [String, Hash] The message to process
    # @param context [Context] Execution context
    # @param thread_id [String] Thread ID to execute in
    # @return [String] The response
    def receive_in_thread(message, context:, thread_id:)
      original_session = @session_id
      original_history = @history.dup

      # Switch to delegation thread
      @session_id = thread_id
      @history = []
      reload_history_from_session

      begin
        result = receive(message, context: context)
        result
      ensure
        # Restore original session
        @session_id = original_session
        @history = original_history
      end
    end

    # Create a new root thread and switch to it.
    # @param name [String, nil] Optional thread name
    # @return [String] New thread ID
    def new_thread(name: nil)
      return nil unless session_store

      @session_id = session_store.create_thread(
        po_name: self.name,
        name: name,
        thread_type: "root"
      )
      @history = []
      @session_id
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

          result = if capability.is_a?(PromptObject)
                     # PO-to-PO call: create isolated delegation thread
                     execute_po_delegation(capability, tc, context)
                   else
                     # Primitive call: execute directly
                     capability.receive(tc.arguments, context: context)
                   end

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

    # Execute a delegation to another PO in an isolated thread.
    # @param target_po [PromptObject] The PO to delegate to
    # @param tool_call [ToolCall] The tool call details
    # @param context [Context] Execution context
    # @return [String] The response
    def execute_po_delegation(target_po, tool_call, context)
      # Create a delegation thread in the target PO
      delegation_thread = target_po.create_delegation_thread(
        parent_po: name,
        parent_session_id: @session_id,
        parent_message_id: get_last_message_id
      )

      if delegation_thread
        # Execute in isolated thread
        target_po.receive_in_thread(tool_call.arguments, context: context, thread_id: delegation_thread)
      else
        # Fallback: execute in target's current session (no session store)
        target_po.receive(tool_call.arguments, context: context)
      end
    end

    # Get the ID of the last message in the current session.
    # @return [Integer, nil]
    def get_last_message_id
      return nil unless session_store && @session_id

      messages = session_store.get_messages(@session_id)
      messages.last&.dig(:id)
    end

    # Notify the history updated callback if registered.
    # Used for real-time UI updates during the receive loop.
    def notify_history_updated
      @on_history_updated&.call(self, @session_id, @history)
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
          tool_calls: tool_calls_data,
          usage: msg[:usage]
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
