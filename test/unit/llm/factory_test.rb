# frozen_string_literal: true

require_relative "../../test_helper"

class FactoryTest < PromptObjectsTest
  def test_create_openai_adapter
    adapter = PromptObjects::LLM::Factory.create(provider: "openai", api_key: "test-key")
    assert_instance_of PromptObjects::LLM::OpenAIAdapter, adapter
  end

  def test_create_anthropic_adapter
    adapter = PromptObjects::LLM::Factory.create(provider: "anthropic", api_key: "test-key")
    assert_instance_of PromptObjects::LLM::AnthropicAdapter, adapter
  end

  def test_create_gemini_adapter
    adapter = PromptObjects::LLM::Factory.create(provider: "gemini", api_key: "test-key")
    assert_instance_of PromptObjects::LLM::GeminiAdapter, adapter
  end

  def test_create_ollama_adapter_uses_openai_adapter
    adapter = PromptObjects::LLM::Factory.create(provider: "ollama")
    assert_instance_of PromptObjects::LLM::OpenAIAdapter, adapter
  end

  def test_create_openrouter_adapter_uses_openai_adapter
    adapter = PromptObjects::LLM::Factory.create(provider: "openrouter", api_key: "test-key")
    assert_instance_of PromptObjects::LLM::OpenAIAdapter, adapter
  end

  def test_create_unknown_provider_raises
    assert_raises(PromptObjects::Error) do
      PromptObjects::LLM::Factory.create(provider: "unknown")
    end
  end

  def test_ollama_does_not_require_api_key
    # Should not raise — uses api_key_default
    adapter = PromptObjects::LLM::Factory.create(provider: "ollama")
    assert adapter
  end

  def test_providers_includes_new_providers
    providers = PromptObjects::LLM::Factory.providers
    assert_includes providers, "ollama"
    assert_includes providers, "openrouter"
  end

  def test_default_model_for_ollama
    assert_equal "llama3.2", PromptObjects::LLM::Factory.default_model("ollama")
  end

  def test_default_model_for_openrouter
    assert_equal "meta-llama/llama-3.3-70b-instruct", PromptObjects::LLM::Factory.default_model("openrouter")
  end

  def test_models_for_openrouter_returns_static_list
    models = PromptObjects::LLM::Factory.models_for("openrouter")
    assert models.length > 0
    assert_includes models, "meta-llama/llama-3.3-70b-instruct"
  end

  def test_provider_info_for_ollama
    info = PromptObjects::LLM::Factory.provider_info("ollama")
    assert info
    assert_equal "OpenAIAdapter", info[:adapter]
    assert_equal true, info[:local]
    assert_equal "http://localhost:11434/v1", info[:base_url]
  end

  def test_provider_info_for_openrouter
    info = PromptObjects::LLM::Factory.provider_info("openrouter")
    assert info
    assert_equal "OpenAIAdapter", info[:adapter]
    assert_equal "https://openrouter.ai/api/v1", info[:base_url]
    assert info[:extra_headers]
  end

  def test_ollama_provider_name_in_usage
    adapter = PromptObjects::LLM::Factory.create(provider: "ollama")
    # Verify the provider name is passed through for usage tracking
    raw = { "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 } }
    usage = adapter.send(:extract_usage, raw)
    assert_equal "ollama", usage[:provider]
  end

  def test_openrouter_provider_name_in_usage
    adapter = PromptObjects::LLM::Factory.create(provider: "openrouter", api_key: "test-key")
    raw = { "usage" => { "prompt_tokens" => 10, "completion_tokens" => 5 } }
    usage = adapter.send(:extract_usage, raw)
    assert_equal "openrouter", usage[:provider]
  end

  def test_discover_ollama_models_handles_unreachable
    # Use a port that's almost certainly not running anything
    models = PromptObjects::LLM::Factory.discover_ollama_models("http://localhost:1/v1")
    assert_equal [], models
  end
end
