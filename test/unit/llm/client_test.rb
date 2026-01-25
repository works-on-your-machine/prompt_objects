# frozen_string_literal: true

require_relative "../../test_helper"

# Tests for LLM Client and ToolCall classes.
class LLMClientTest < PromptObjectsTest
  def setup
    super
    @tool_call_object = PromptObjects::LLM::ToolCall.new(
      id: "call_123",
      name: "read_file",
      arguments: { path: "/tmp/test.txt" }
    )
    @tool_call_hash = {
      id: "call_123",
      name: "read_file",
      arguments: { path: "/tmp/test.txt" }
    }
    @tool_call_hash_string_keys = {
      "id" => "call_123",
      "name" => "read_file",
      "arguments" => { "path" => "/tmp/test.txt" }
    }
  end

  # --- ToolCall class tests ---

  def test_tool_call_method_access
    tc = @tool_call_object
    assert_equal "call_123", tc.id
    assert_equal "read_file", tc.name
    assert_equal({ path: "/tmp/test.txt" }, tc.arguments)
  end

  def test_tool_call_hash_access
    tc = @tool_call_object
    assert_equal "call_123", tc[:id]
    assert_equal "read_file", tc[:name]
    assert_equal({ path: "/tmp/test.txt" }, tc[:arguments])
  end

  def test_tool_call_to_h
    tc = @tool_call_object
    expected = { id: "call_123", name: "read_file", arguments: { path: "/tmp/test.txt" } }
    assert_equal expected, tc.to_h
  end

  def test_tool_call_from_hash_with_symbol_keys
    tc = PromptObjects::LLM::ToolCall.from_hash(@tool_call_hash)
    assert_equal "call_123", tc.id
    assert_equal "read_file", tc.name
  end

  def test_tool_call_from_hash_with_string_keys
    tc = PromptObjects::LLM::ToolCall.from_hash(@tool_call_hash_string_keys)
    assert_equal "call_123", tc.id
    assert_equal "read_file", tc.name
  end

  def test_tool_call_from_hash_returns_tool_call_unchanged
    original = @tool_call_object
    result = PromptObjects::LLM::ToolCall.from_hash(original)
    assert_same original, result
  end

  # --- Client class tests ---

  def test_client_providers
    providers = PromptObjects::LLM::Client.providers
    assert_includes providers, "openai"
    assert_includes providers, "anthropic"
    assert_includes providers, "gemini"
  end

  def test_client_default_models
    assert_equal "gpt-4.1", PromptObjects::LLM::Client.default_model("openai")
    assert_equal "claude-sonnet-4-5", PromptObjects::LLM::Client.default_model("anthropic")
    assert_equal "gemini-2.0-flash", PromptObjects::LLM::Client.default_model("gemini")
  end

  def test_client_available_providers_returns_hash
    available = PromptObjects::LLM::Client.available_providers
    assert_kind_of Hash, available
    assert available.key?("openai")
    assert available.key?("anthropic")
    assert available.key?("gemini")
  end

  def test_client_raises_on_unknown_provider
    assert_raises(PromptObjects::Error) do
      PromptObjects::LLM::Client.new(provider: "unknown_provider", api_key: "test")
    end
  end
end
