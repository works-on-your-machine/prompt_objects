# frozen_string_literal: true

module PromptObjects
  module LLM
    # Anthropic API adapter for LLM calls.
    class AnthropicAdapter
      DEFAULT_MODEL = "claude-haiku-4-5"
      DEFAULT_MAX_TOKENS = 4096

      def initialize(api_key: nil, model: nil, max_tokens: nil)
        @api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY") do
          raise Error, "ANTHROPIC_API_KEY environment variable not set"
        end
        @model = model || DEFAULT_MODEL
        @max_tokens = max_tokens || DEFAULT_MAX_TOKENS
        @client = Anthropic::Client.new(api_key: @api_key)
      end

      # Make a chat completion request.
      # @param system [String] System prompt
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool descriptors (optional)
      # @return [Response] Normalized response
      def chat(system:, messages:, tools: [])
        params = {
          model: @model,
          max_tokens: @max_tokens,
          system: system,
          messages: build_messages(messages)
        }

        # Only include tools if we have any
        if tools.any?
          params[:tools] = convert_tools(tools)
        end

        raw_response = @client.messages.create(**params)
        parse_response(raw_response)
      end

      private

      def build_messages(messages)
        result = []

        messages.each do |msg|
          case msg[:role]
          when :user
            result << { role: "user", content: msg[:content] }
          when :assistant
            content_blocks = []

            # Add text content if present
            if msg[:content] && !msg[:content].empty?
              content_blocks << { type: "text", text: msg[:content] }
            end

            # Add tool_use blocks if present
            if msg[:tool_calls]
              msg[:tool_calls].each do |tc|
                # Handle both ToolCall objects and Hashes (from database)
                tc_id = tc.respond_to?(:id) ? tc.id : (tc[:id] || tc["id"])
                tc_name = tc.respond_to?(:name) ? tc.name : (tc[:name] || tc["name"])
                tc_args = tc.respond_to?(:arguments) ? tc.arguments : (tc[:arguments] || tc["arguments"] || {})

                content_blocks << {
                  type: "tool_use",
                  id: tc_id,
                  name: tc_name,
                  input: tc_args
                }
              end
            end

            result << { role: "assistant", content: content_blocks } if content_blocks.any?
          when :tool
            # Tool results in Anthropic are sent as user messages with tool_result content blocks
            tool_result_blocks = msg[:results].map do |tool_result|
              {
                type: "tool_result",
                tool_use_id: tool_result[:tool_call_id],
                content: tool_result[:content].to_s
              }
            end
            result << { role: "user", content: tool_result_blocks }
          end
        end

        result
      end

      # Convert OpenAI-style tool definitions to Anthropic format
      def convert_tools(tools)
        tools.map do |tool|
          if tool[:type] == "function"
            # OpenAI format with function wrapper
            func = tool[:function]
            {
              name: func[:name],
              description: func[:description],
              input_schema: func[:parameters] || { type: "object", properties: {} }
            }
          else
            # Already in Anthropic format or simple format
            {
              name: tool[:name],
              description: tool[:description],
              input_schema: tool[:input_schema] || tool[:parameters] || { type: "object", properties: {} }
            }
          end
        end
      end

      def parse_response(raw)
        content = ""
        tool_calls = []

        # Raw response is an Anthropic::Message object with content array
        # Note: SDK returns type as Symbol (:text, :tool_use), not String
        raw.content.each do |block|
          case block.type.to_sym
          when :text
            content += block.text
          when :tool_use
            tool_calls << ToolCall.new(
              id: block.id,
              name: block.name,
              arguments: block.input.is_a?(Hash) ? block.input : block.input.to_h
            )
          end
        end

        Response.new(content: content, tool_calls: tool_calls, raw: raw, usage: extract_usage(raw))
      end

      def extract_usage(raw)
        return nil unless raw.respond_to?(:usage) && raw.usage

        usage = raw.usage
        {
          input_tokens: usage.respond_to?(:input_tokens) ? usage.input_tokens : 0,
          output_tokens: usage.respond_to?(:output_tokens) ? usage.output_tokens : 0,
          cache_creation_tokens: usage.respond_to?(:cache_creation_input_tokens) ? (usage.cache_creation_input_tokens || 0) : 0,
          cache_read_tokens: usage.respond_to?(:cache_read_input_tokens) ? (usage.cache_read_input_tokens || 0) : 0,
          model: @model,
          provider: "anthropic"
        }
      end
    end
  end
end
