# frozen_string_literal: true

require "net/http"
require "json"

module PromptObjects
  module LLM
    # Factory for creating LLM adapters based on provider name.
    # Provides a unified interface for switching between providers.
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
          default_model: "gemini-3-flash-preview",
          models: %w[gemini-3-flash-preview gemini-2.5-pro gemini-2.5-flash]
        },
        "ollama" => {
          adapter: "OpenAIAdapter",
          env_key: nil,
          api_key_default: "ollama",
          default_model: "llama3.2",
          models: [],  # Dynamic — populated from Ollama API
          base_url: "http://localhost:11434/v1",
          local: true
        },
        "openrouter" => {
          adapter: "OpenAIAdapter",
          env_key: "OPENROUTER_API_KEY",
          default_model: "meta-llama/llama-3.3-70b-instruct",
          models: %w[
            meta-llama/llama-3.3-70b-instruct
            meta-llama/llama-4-scout
            meta-llama/llama-4-maverick
            mistralai/mistral-large-2411
            google/gemma-3-27b-it
            deepseek/deepseek-r1
            qwen/qwen-2.5-72b-instruct
          ],
          base_url: "https://openrouter.ai/api/v1",
          extra_headers: {
            "HTTP-Referer" => "https://github.com/prompt-objects",
            "X-Title" => "PromptObjects"
          }
        }
      }.freeze

      DEFAULT_PROVIDER = "anthropic"

      class << self
        # Create an adapter for the given provider.
        # @param provider [String] Provider name
        # @param model [String, nil] Optional model override
        # @param api_key [String, nil] Optional API key override
        # @return [OpenAIAdapter, AnthropicAdapter, GeminiAdapter]
        def create(provider: nil, model: nil, api_key: nil)
          provider_name = (provider || DEFAULT_PROVIDER).to_s.downcase
          config = PROVIDERS[provider_name]

          raise Error, "Unknown LLM provider: #{provider_name}" unless config

          # Resolve API key: explicit > env var > default
          resolved_key = api_key ||
            (config[:env_key] && ENV[config[:env_key]]) ||
            config[:api_key_default]

          adapter_class = LLM.const_get(config[:adapter])

          adapter_args = { api_key: resolved_key, model: model || config[:default_model] }
          adapter_args[:base_url] = config[:base_url] if config[:base_url]
          adapter_args[:extra_headers] = config[:extra_headers] if config[:extra_headers]
          # Pass provider name for usage tracking (OpenAI adapter handles multiple providers)
          adapter_args[:provider_name] = provider_name if config[:adapter] == "OpenAIAdapter"

          adapter_class.new(**adapter_args)
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

        # Check which providers are available (have API keys or are local).
        # @return [Hash<String, Boolean>]
        def available_providers
          PROVIDERS.transform_values do |config|
            if config[:local]
              check_local_provider(config[:base_url])
            elsif config[:env_key]
              ENV.key?(config[:env_key])
            else
              true
            end
          end
        end

        # Get the default model for a provider.
        # @param provider [String] Provider name
        # @return [String, nil]
        def default_model(provider)
          PROVIDERS.dig(provider.to_s.downcase, :default_model)
        end

        # Get available models for a provider.
        # For Ollama, dynamically discovers installed models.
        # @param provider [String] Provider name
        # @return [Array<String>]
        def models_for(provider)
          config = PROVIDERS[provider.to_s.downcase]
          return [] unless config

          # Dynamic model discovery for Ollama
          if config[:local] && provider.to_s.downcase == "ollama"
            models = discover_ollama_models(config[:base_url])
            return models unless models.empty?
          end

          config[:models] || []
        end

        # Discover installed Ollama models.
        # @param base_url [String] Ollama API base URL (with /v1 suffix)
        # @return [Array<String>] Model names
        def discover_ollama_models(base_url = "http://localhost:11434/v1")
          # Ollama's model list endpoint is at /api/tags (not under /v1)
          tags_url = base_url.sub(%r{/v1\z}, "") + "/api/tags"
          uri = URI(tags_url)
          response = Net::HTTP.get_response(uri)
          return [] unless response.is_a?(Net::HTTPSuccess)

          data = JSON.parse(response.body)
          (data["models"] || []).map { |m| m["name"] }
        rescue StandardError
          []
        end

        private

        def check_local_provider(base_url)
          return false unless base_url
          tags_url = base_url.sub(%r{/v1\z}, "") + "/api/tags"
          uri = URI(tags_url)
          response = Net::HTTP.get_response(uri)
          response.is_a?(Net::HTTPSuccess)
        rescue StandardError
          false
        end
      end
    end
  end
end
