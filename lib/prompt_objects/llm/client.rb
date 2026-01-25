# frozen_string_literal: true

require "ruby_llm"
require "securerandom"

module PromptObjects
  module LLM
    # Simple LLM client using the ruby_llm gem.
    # Provides a unified interface across OpenAI, Anthropic, Gemini, and other providers.
    class Client
      attr_reader :provider, :model

      PROVIDERS = {
        "openai" => { symbol: :openai, default_model: "gpt-4.1" },
        "anthropic" => { symbol: :anthropic, default_model: "claude-sonnet-4-5" },
        "gemini" => { symbol: :gemini, default_model: "gemini-2.0-flash" }
      }.freeze

      def initialize(provider: "anthropic", model: nil, api_key: nil)
        @provider = provider.to_s.downcase
        config = PROVIDERS[@provider]
        raise Error, "Unknown LLM provider: #{@provider}" unless config

        @provider_symbol = config[:symbol]
        @model = model || config[:default_model]

        configure_api_key(api_key)
      end

      # Send a chat completion request.
      # @param system [String] System prompt
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Hash>] Tool descriptors in OpenAI format
      # @return [Hash] Response with :content and :tool_calls
      def chat(system:, messages:, tools: [])
        chat_instance = RubyLLM.chat(model: @model, provider: @provider_symbol)
        chat_instance.with_instructions(system)

        # Register tools
        tools.each { |tool_def| chat_instance.with_tool(build_tool_class(tool_def)) }

        # Populate conversation history
        populate_history(chat_instance, messages)

        # Get completion
        response = chat_instance.complete
        normalize_response(response)
      end

      # List available providers with their configuration status.
      # @return [Hash<String, Boolean>]
      def self.available_providers
        {
          "openai" => ENV.key?("OPENAI_API_KEY"),
          "anthropic" => ENV.key?("ANTHROPIC_API_KEY"),
          "gemini" => ENV.key?("GEMINI_API_KEY")
        }
      end

      # Get default model for a provider.
      # @param provider [String]
      # @return [String, nil]
      def self.default_model(provider)
        PROVIDERS.dig(provider.to_s.downcase, :default_model)
      end

      # List all supported providers.
      # @return [Array<String>]
      def self.providers
        PROVIDERS.keys
      end

      private

      def configure_api_key(api_key)
        RubyLLM.configure do |config|
          case @provider
          when "openai"
            config.openai_api_key = api_key || ENV.fetch("OPENAI_API_KEY") do
              raise Error, "OPENAI_API_KEY environment variable not set"
            end
          when "anthropic"
            config.anthropic_api_key = api_key || ENV.fetch("ANTHROPIC_API_KEY") do
              raise Error, "ANTHROPIC_API_KEY environment variable not set"
            end
          when "gemini"
            config.gemini_api_key = api_key || ENV.fetch("GEMINI_API_KEY") do
              raise Error, "GEMINI_API_KEY environment variable not set"
            end
          end
        end
      end

      def build_tool_class(tool_def)
        func = tool_def[:function] || tool_def["function"]
        name = func[:name] || func["name"]
        desc = func[:description] || func["description"]
        params = func[:parameters] || func["parameters"] || {}
        properties = params[:properties] || params["properties"] || {}

        # Create anonymous tool class
        Class.new(RubyLLM::Tool) do
          description desc

          properties.each do |param_name, param_schema|
            param_desc = param_schema[:description] || param_schema["description"] || ""
            param param_name.to_sym, desc: param_desc
          end

          # Placeholder execute - actual execution handled by PromptObject
          define_method(:execute) { |**args| args }
        end
      end

      def populate_history(chat_instance, messages)
        messages.each do |msg|
          case msg[:role]
          when :user
            chat_instance.add_message(role: :user, content: msg[:content])
          when :assistant
            add_assistant_message(chat_instance, msg)
          when :tool
            add_tool_results(chat_instance, msg)
          end
        end
      end

      def add_assistant_message(chat_instance, msg)
        if msg[:tool_calls]&.any?
          tool_calls_data = msg[:tool_calls].map do |tc|
            {
              id: extract_field(tc, :id),
              name: extract_field(tc, :name),
              arguments: extract_field(tc, :arguments) || {}
            }
          end
          chat_instance.add_message(role: :assistant, content: msg[:content] || "", tool_calls: tool_calls_data)
        else
          chat_instance.add_message(role: :assistant, content: msg[:content] || "")
        end
      end

      def add_tool_results(chat_instance, msg)
        msg[:results]&.each do |result|
          chat_instance.add_message(
            role: :tool,
            tool_call_id: result[:tool_call_id],
            content: result[:content].to_s
          )
        end
      end

      def extract_field(obj, field)
        if obj.respond_to?(field)
          obj.send(field)
        else
          obj[field] || obj[field.to_s]
        end
      end

      def normalize_response(response)
        return { content: "", tool_calls: [] } unless response

        tool_calls = if response.respond_to?(:tool_calls) && response.tool_calls&.any?
                       response.tool_calls.map do |tc|
                         ToolCall.new(
                           id: tc.id || generate_call_id(tc.name),
                           name: tc.name,
                           arguments: normalize_arguments(tc.arguments)
                         )
                       end
                     else
                       []
                     end

        { content: response.content || "", tool_calls: tool_calls }
      end

      def normalize_arguments(args)
        return {} unless args
        args.is_a?(Hash) ? args : args.to_h
      end

      def generate_call_id(name)
        "call_#{name}_#{SecureRandom.hex(8)}"
      end
    end
  end
end
