# frozen_string_literal: true

module PromptObjects
  module LLM
    # Factory for creating LLM adapters based on provider name.
    # Provides a unified interface for switching between OpenAI, Anthropic, and Gemini.
    class Factory
      PROVIDERS = {
        "openai" => {
          adapter: "OpenAIAdapter",
          env_key: "OPENAI_API_KEY",
          default_model: "gpt-5.2",
          models: %w[gpt-5.2 gpt-4.1 gpt-4.1-mini gpt-4.5-preview o3-mini o1]
        },
        "anthropic" => {
          adapter: "AnthropicAdapter",
          env_key: "ANTHROPIC_API_KEY",
          default_model: "claude-haiku-4-5",
          models: %w[claude-haiku-4-5 claude-sonnet-4-5 claude-opus-4]
        },
        "gemini" => {
          adapter: "GeminiAdapter",
          env_key: "GEMINI_API_KEY",
          default_model: "gemini-3-flash",
          models: %w[gemini-3-flash gemini-2.5-pro gemini-2.5-flash]
        }
      }.freeze

      DEFAULT_PROVIDER = "anthropic"

      class << self
        # Create an adapter for the given provider.
        # @param provider [String] Provider name (openai, anthropic, gemini)
        # @param model [String, nil] Optional model override
        # @param api_key [String, nil] Optional API key override
        # @return [OpenAIAdapter, AnthropicAdapter, GeminiAdapter]
        def create(provider: nil, model: nil, api_key: nil)
          provider_name = (provider || DEFAULT_PROVIDER).to_s.downcase
          config = PROVIDERS[provider_name]

          raise Error, "Unknown LLM provider: #{provider_name}" unless config

          adapter_class = LLM.const_get(config[:adapter])
          adapter_class.new(api_key: api_key, model: model)
        end

        # List available providers.
        # @return [Array<String>]
        def providers
          PROVIDERS.keys
        end

        # Get info about a provider.
        # @param provider [String] Provider name
        # @return [Hash, nil]
        def provider_info(provider)
          PROVIDERS[provider.to_s.downcase]
        end

        # Check which providers have API keys configured.
        # @return [Hash<String, Boolean>]
        def available_providers
          PROVIDERS.transform_values do |config|
            ENV.key?(config[:env_key])
          end
        end

        # Get the default model for a provider.
        # @param provider [String] Provider name
        # @return [String, nil]
        def default_model(provider)
          PROVIDERS.dig(provider.to_s.downcase, :default_model)
        end

        # Get available models for a provider.
        # @param provider [String] Provider name
        # @return [Array<String>]
        def models_for(provider)
          PROVIDERS.dig(provider.to_s.downcase, :models) || []
        end
      end
    end
  end
end
