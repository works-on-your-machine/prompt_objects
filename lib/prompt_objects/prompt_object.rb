# frozen_string_literal: true

module PromptObjects
  # A Prompt Object is a capability backed by an LLM.
  # It interprets messages semantically using its markdown "soul" as the system prompt.
  class PromptObject < Capability
    attr_reader :config, :body, :history

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

      @history << { role: :user, content: content, from: from }
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
          @history << {
            role: :assistant,
            # Don't include content when there are tool calls - force LLM to
            # wait for tool results before generating a response. This prevents
            # the model from "hedging" by generating both a response AND a tool call.
            content: nil,
            tool_calls: response.tool_calls
          }
          @history << { role: :tool, results: results }
        else
          # No tool calls - we have our final response
          @history << { role: :assistant, content: response.content }
          @state = :idle
          return response.content
        end
      end
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

      tool_calls.map do |tc|
        capability = @env.registry&.get(tc.name)

        if capability
          # Log the outgoing message
          @env.bus.publish(from: name, to: tc.name, message: tc.arguments)

          # Set context for nested calls
          context.current_capability = tc.name

          result = capability.receive(tc.arguments, context: context)

          # Restore context
          context.current_capability = previous_capability

          # Log the response
          @env.bus.publish(from: tc.name, to: name, message: result)

          { tool_call_id: tc.id, content: result }
        else
          { tool_call_id: tc.id, content: "Unknown capability: #{tc.name}" }
        end
      end
    end
  end
end
