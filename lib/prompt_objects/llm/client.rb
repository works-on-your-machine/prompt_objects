# frozen_string_literal: true

require "ruby_llm"
require "securerandom"

module PromptObjects
  module LLM
    # Simple LLM client using the ruby_llm gem.
    # Provides a unified interface across OpenAI, Anthropic, Gemini, and other providers.
    #
    # This client works with RubyLLM::Tool classes for native tool execution.
    # Tools must be subclasses of RubyLLM::Tool (like Primitives::Base).
    class Client
      attr_reader :provider, :model

      PROVIDERS = {
        "openai" => { symbol: :openai, default_model: "gpt-4.1" },
        "anthropic" => { symbol: :anthropic, default_model: "claude-sonnet-4-5" },
        "gemini" => { symbol: :gemini, default_model: "gemini-2.0-flash" },
        "ollama" => { symbol: :ollama, default_model: "llama3.2" }
      }.freeze

      def initialize(provider: "anthropic", model: nil, api_key: nil)
        @provider = provider.to_s.downcase
        config = PROVIDERS[@provider]
        raise Error, "Unknown LLM provider: #{@provider}" unless config

        @provider_symbol = config[:symbol]
        @model = model || config[:default_model]

        configure_api_key(api_key)
      end

      # Send a chat completion request with native RubyLLM tool execution.
      #
      # @param system [String] System prompt
      # @param messages [Array<Hash>] Conversation history
      # @param tools [Array<Class<RubyLLM::Tool>>] Tool classes (not instances)
      # @param context [Object, nil] Context to inject into tool classes
      # @param on_tool_call [Proc, nil] Callback when a tool is called
      # @param on_tool_result [Proc, nil] Callback when a tool returns
      # @param on_message [Proc, nil] Callback for each message in the conversation
      # @return [Hash] Response with :content and :tool_calls (for history tracking)
      def chat(system:, messages:, tools: [], context: nil, on_tool_call: nil, on_tool_result: nil, on_message: nil)
        chat_instance = RubyLLM.chat(model: @model, provider: @provider_symbol)
        chat_instance.with_instructions(system)

        # Inject context into tool classes and register them
        if tools.any?
          tools.each do |tool_class|
            tool_class.context = context if tool_class.respond_to?(:context=)
          end
          chat_instance.with_tools(*tools)
        end

        # Set up callbacks
        if on_tool_call
          chat_instance.on_tool_call { |tc| on_tool_call.call(tc) }
        end

        if on_tool_result
          chat_instance.on_tool_result { |result| on_tool_result.call(result) }
        end

        # Populate conversation history
        populate_history(chat_instance, messages)

        # Get the last user message to send
        last_user_message = messages.reverse.find { |m| m[:role] == :user }
        user_content = last_user_message ? last_user_message[:content] : ""

        # Use ask() which handles the full tool execution loop
        response = chat_instance.ask(user_content)

        normalize_response(response, chat_instance)
      end

      # List available providers with their configuration status.
      # @return [Hash<String, Boolean>]
      def self.available_providers
        {
          "openai" => ENV.key?("OPENAI_API_KEY"),
          "anthropic" => ENV.key?("ANTHROPIC_API_KEY"),
          "gemini" => ENV.key?("GEMINI_API_KEY"),
          "ollama" => true  # Ollama is always available (local)
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
          when "ollama"
            config.ollama_api_base = api_key || ENV.fetch("OLLAMA_API_BASE", "http://localhost:11434")
          end
        end
      end

      def populate_history(chat_instance, messages)
        # Skip the last user message since we'll send it via ask()
        messages_to_add = messages[0...-1] || []

        messages_to_add.each do |msg|
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
          # Convert tool calls to Hash format expected by RubyLLM
          # RubyLLM's format_tool_calls expects: { call_id => ToolCall }
          tool_calls_hash = msg[:tool_calls].each_with_object({}) do |tc, hash|
            tc_id = extract_field(tc, :id)
            tool_call = RubyLLM::ToolCall.new(
              id: tc_id,
              name: extract_field(tc, :name),
              arguments: extract_field(tc, :arguments) || {}
            )
            hash[tc_id] = tool_call
          end
          chat_instance.add_message(role: :assistant, content: msg[:content] || "", tool_calls: tool_calls_hash)
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

      def normalize_response(response, chat_instance)
        return { content: "", tool_calls: [], messages: [] } unless response

        # Get the conversation messages for history tracking
        # RubyLLM manages the full conversation internally
        conversation_messages = extract_conversation_messages(chat_instance)

        {
          content: response.content || "",
          tool_calls: [],  # Tools already executed by RubyLLM
          messages: conversation_messages
        }
      end

      # Extract messages from RubyLLM chat instance for persistence
      def extract_conversation_messages(chat_instance)
        return [] unless chat_instance.respond_to?(:messages)

        chat_instance.messages.map do |msg|
          base = { role: msg.role.to_sym, content: msg.content }

          if msg.respond_to?(:tool_calls) && msg.tool_calls&.any?
            # RubyLLM returns tool_calls as a Hash: { call_id => ToolCall }
            tool_calls_collection = msg.tool_calls.is_a?(Hash) ? msg.tool_calls.values : msg.tool_calls

            base[:tool_calls] = tool_calls_collection.map do |tc|
              if tc.is_a?(RubyLLM::ToolCall)
                ToolCall.new(
                  id: tc.id.to_s,
                  name: tc.name.to_s,
                  arguments: tc.arguments.is_a?(Hash) ? tc.arguments : {}
                )
              else
                # Fallback for other formats
                tc_id = extract_tool_call_field(tc, :id)
                tc_name = extract_tool_call_field(tc, :name)
                tc_args = extract_tool_call_field(tc, :arguments) || {}

                ToolCall.new(
                  id: tc_id || generate_call_id(tc_name),
                  name: tc_name.to_s,
                  arguments: tc_args.is_a?(Hash) ? tc_args : {}
                )
              end
            end
          end

          base
        end
      end

      # Extract a field from a tool call, handling different formats
      def extract_tool_call_field(tc, field)
        if tc.respond_to?(field)
          tc.send(field)
        elsif tc.is_a?(Hash)
          tc[field] || tc[field.to_s]
        elsif tc.is_a?(Array)
          # Some providers return [id, name, arguments] format
          case field
          when :id then tc[0]
          when :name then tc[1]
          when :arguments then tc[2]
          end
        end
      end

      def generate_call_id(name)
        "call_#{name}_#{SecureRandom.hex(8)}"
      end
    end
  end
end
