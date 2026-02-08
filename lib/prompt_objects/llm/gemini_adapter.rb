# frozen_string_literal: true

require "net/http"
require "uri"
require "json"
require "securerandom"

module PromptObjects
  module LLM
    # Google Gemini API adapter for LLM calls.
    # Uses direct HTTP calls to the Gemini REST API.
    class GeminiAdapter
      DEFAULT_MODEL = "gemini-3-flash-preview"
      API_BASE_URL = "https://generativelanguage.googleapis.com/v1beta"

      def initialize(api_key: nil, model: nil)
        @api_key = api_key || ENV.fetch("GEMINI_API_KEY") do
          raise Error, "GEMINI_API_KEY environment variable not set"
        end
        @model = model || DEFAULT_MODEL
      end

      # Make a chat completion request.
      # @param system [String] System prompt
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool descriptors (optional)
      # @return [Response] Normalized response
      def chat(system:, messages:, tools: [])
        body = {
          system_instruction: build_system_instruction(system),
          contents: build_contents(messages)
        }

        # Only include tools if we have any
        if tools.any?
          body[:tools] = build_tools(tools)
          body[:tool_config] = { function_calling_config: { mode: "AUTO" } }
        end

        raw_response = make_request(body)
        parse_response(raw_response)
      end

      private

      def build_system_instruction(system)
        {
          parts: [{ text: system }]
        }
      end

      def build_contents(messages)
        result = []
        # Track tool calls from the last assistant message for name lookup
        last_tool_calls = {}

        messages.each do |msg|
          case msg[:role]
          when :user
            result << {
              role: "user",
              parts: [{ text: msg[:content] }]
            }
          when :assistant
            parts = []
            parts << { text: msg[:content] } if msg[:content] && !msg[:content].empty?
            if msg[:tool_calls]
              # Store tool calls for potential name lookup in tool results
              last_tool_calls = {}
              msg[:tool_calls].each do |tc|
                # Handle both ToolCall objects and Hashes (from database)
                tc_id = tc.respond_to?(:id) ? tc.id : (tc[:id] || tc["id"])
                tc_name = tc.respond_to?(:name) ? tc.name : (tc[:name] || tc["name"])
                tc_args = tc.respond_to?(:arguments) ? tc.arguments : (tc[:arguments] || tc["arguments"] || {})

                last_tool_calls[tc_id] = tc_name
                parts << {
                  functionCall: {
                    name: tc_name,
                    args: tc_args
                  }
                }
              end
            end
            result << { role: "model", parts: parts } if parts.any?
          when :tool
            # Tool results go back as a user message with functionResponse parts
            parts = msg[:results].map do |tool_result|
              # Get name from result, or look it up from the previous assistant's tool_calls
              name = tool_result[:name] || last_tool_calls[tool_result[:tool_call_id]] || "unknown"
              {
                functionResponse: {
                  name: name,
                  response: parse_tool_response_content(tool_result[:content])
                }
              }
            end
            result << { role: "user", parts: parts }
          end
        end

        result
      end

      def parse_tool_response_content(content)
        # Try to parse as JSON, otherwise wrap in a result object
        if content.is_a?(String)
          begin
            JSON.parse(content)
          rescue JSON::ParserError
            { result: content }
          end
        else
          content
        end
      end

      def build_tools(tools)
        # Convert OpenAI-style tool format to Gemini function declarations
        function_declarations = tools.map do |tool|
          func = tool[:function] || tool["function"]
          {
            name: func[:name] || func["name"],
            description: func[:description] || func["description"],
            parameters: convert_parameters(func[:parameters] || func["parameters"])
          }
        end

        [{ functionDeclarations: function_declarations }]
      end

      def convert_parameters(params)
        return {} unless params

        # Gemini uses OpenAPI-style parameters, similar to OpenAI
        # but we need to ensure proper structure
        result = {
          type: params[:type] || params["type"] || "object"
        }

        if params[:properties] || params["properties"]
          result[:properties] = params[:properties] || params["properties"]
        end

        if params[:required] || params["required"]
          result[:required] = params[:required] || params["required"]
        end

        result
      end

      def make_request(body)
        uri = URI("#{API_BASE_URL}/models/#{@model}:generateContent?key=#{@api_key}")

        http = Net::HTTP.new(uri.host, uri.port)
        http.use_ssl = true
        http.read_timeout = 120
        http.open_timeout = 30

        request = Net::HTTP::Post.new(uri)
        request["Content-Type"] = "application/json"
        request.body = body.to_json

        response = http.request(request)

        unless response.is_a?(Net::HTTPSuccess)
          error_body = begin
            JSON.parse(response.body)
          rescue StandardError
            response.body
          end
          raise Error, "Gemini API error (#{response.code}): #{error_body}"
        end

        JSON.parse(response.body)
      end

      def parse_response(raw)
        candidate = raw.dig("candidates", 0)
        content_obj = candidate&.dig("content")

        return Response.new(content: "", raw: raw) unless content_obj

        text_content = ""
        tool_calls = []

        content_obj["parts"]&.each do |part|
          if part["text"]
            text_content += part["text"]
          elsif part["functionCall"]
            tool_calls << parse_function_call(part["functionCall"])
          end
        end

        Response.new(content: text_content, tool_calls: tool_calls, raw: raw, usage: extract_usage(raw))
      end

      def extract_usage(raw)
        meta = raw["usageMetadata"]
        return nil unless meta

        {
          input_tokens: meta["promptTokenCount"] || 0,
          output_tokens: meta["candidatesTokenCount"] || 0,
          model: @model,
          provider: "gemini"
        }
      end

      def parse_function_call(fc)
        # Gemini doesn't use tool_call_id like OpenAI, so we generate one
        # based on the function name and a random suffix
        ToolCall.new(
          id: "call_#{fc['name']}_#{SecureRandom.hex(8)}",
          name: fc["name"],
          arguments: fc["args"] || {}
        )
      end
    end
  end
end
