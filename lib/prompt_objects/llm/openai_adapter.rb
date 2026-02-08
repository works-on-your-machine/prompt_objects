# frozen_string_literal: true

module PromptObjects
  module LLM
    # OpenAI API adapter for LLM calls.
    class OpenAIAdapter
      DEFAULT_MODEL = "gpt-5.2"

      def initialize(api_key: nil, model: nil, base_url: nil, extra_headers: nil, provider_name: nil)
        @api_key = api_key || ENV.fetch("OPENAI_API_KEY") do
          raise Error, "OPENAI_API_KEY environment variable not set"
        end
        @model = model || DEFAULT_MODEL
        @provider_name = provider_name || "openai"

        client_opts = { access_token: @api_key }
        client_opts[:uri_base] = base_url if base_url
        client_opts[:extra_headers] = extra_headers if extra_headers
        @client = OpenAI::Client.new(**client_opts)
      end

      # Make a chat completion request.
      # @param system [String] System prompt
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool descriptors (optional)
      # @return [Response] Normalized response
      def chat(system:, messages:, tools: [])
        params = {
          model: @model,
          messages: build_messages(system, messages)
        }

        # Only include tools if we have any
        if tools.any?
          params[:tools] = tools
          params[:tool_choice] = "auto"
        end

        raw_response = @client.chat(parameters: params)
        parse_response(raw_response)
      end

      private

      def build_messages(system, messages)
        result = [{ role: "system", content: system }]

        messages.each do |msg|
          case msg[:role]
          when :user
            result << { role: "user", content: msg[:content] }
          when :assistant
            assistant_msg = { role: "assistant" }
            assistant_msg[:content] = msg[:content] if msg[:content]
            if msg[:tool_calls]
              assistant_msg[:tool_calls] = msg[:tool_calls].map do |tc|
                # Handle both ToolCall objects and Hashes (from database)
                tc_id = tc.respond_to?(:id) ? tc.id : (tc[:id] || tc["id"])
                tc_name = tc.respond_to?(:name) ? tc.name : (tc[:name] || tc["name"])
                tc_args = tc.respond_to?(:arguments) ? tc.arguments : (tc[:arguments] || tc["arguments"] || {})

                {
                  id: tc_id,
                  type: "function",
                  function: { name: tc_name, arguments: tc_args.to_json }
                }
              end
            end
            result << assistant_msg
          when :tool
            msg[:results].each do |tool_result|
              result << {
                role: "tool",
                tool_call_id: tool_result[:tool_call_id],
                content: tool_result[:content].to_s
              }
            end
          end
        end

        result
      end

      def parse_response(raw)
        choice = raw.dig("choices", 0)
        message = choice&.dig("message")

        return Response.new(content: "", raw: raw, usage: extract_usage(raw)) unless message

        content = message["content"] || ""
        tool_calls = parse_tool_calls(message["tool_calls"])

        Response.new(content: content, tool_calls: tool_calls, raw: raw, usage: extract_usage(raw))
      end

      def extract_usage(raw)
        usage = raw["usage"]
        return nil unless usage

        {
          input_tokens: usage["prompt_tokens"] || 0,
          output_tokens: usage["completion_tokens"] || 0,
          model: @model,
          provider: @provider_name
        }
      end

      def parse_tool_calls(raw_tool_calls)
        return [] unless raw_tool_calls

        raw_tool_calls.map do |tc|
          ToolCall.new(
            id: tc["id"],
            name: tc.dig("function", "name"),
            arguments: JSON.parse(tc.dig("function", "arguments") || "{}")
          )
        end
      end
    end
  end
end
