# frozen_string_literal: true

require_relative "../../test_helper"

# Tests for LLM adapter message building - ensures they handle both
# ToolCall objects (from live conversations) and Hashes (from database).
class LLMAdaptersTest < PromptObjectsTest
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

  # --- OpenAI Adapter tests ---

  def test_openai_build_messages_with_tool_call_objects
    # Skip if no API key (we're just testing message building, not API calls)
    adapter = create_openai_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_object] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_messages, "System prompt", messages)

    # Check assistant message has tool_calls
    assistant_msg = built.find { |m| m[:role] == "assistant" }
    assert assistant_msg[:tool_calls]
    assert_equal "call_123", assistant_msg[:tool_calls].first[:id]
    assert_equal "read_file", assistant_msg[:tool_calls].first[:function][:name]
  end

  def test_openai_build_messages_with_tool_call_hashes
    adapter = create_openai_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_hash] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_messages, "System prompt", messages)

    assistant_msg = built.find { |m| m[:role] == "assistant" }
    assert assistant_msg[:tool_calls]
    assert_equal "call_123", assistant_msg[:tool_calls].first[:id]
  end

  # --- Anthropic Adapter tests ---

  def test_anthropic_build_messages_with_tool_call_objects
    adapter = create_anthropic_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_object] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_messages, messages)

    assistant_msg = built.find { |m| m[:role] == "assistant" }
    tool_use_block = assistant_msg[:content].find { |b| b[:type] == "tool_use" }
    assert tool_use_block
    assert_equal "call_123", tool_use_block[:id]
    assert_equal "read_file", tool_use_block[:name]
  end

  def test_anthropic_build_messages_with_tool_call_hashes
    adapter = create_anthropic_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_hash] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_messages, messages)

    assistant_msg = built.find { |m| m[:role] == "assistant" }
    tool_use_block = assistant_msg[:content].find { |b| b[:type] == "tool_use" }
    assert tool_use_block
    assert_equal "call_123", tool_use_block[:id]
  end

  # --- Gemini Adapter tests ---

  def test_gemini_build_contents_with_tool_call_objects
    adapter = create_gemini_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_object] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_contents, messages)

    model_msg = built.find { |m| m[:role] == "model" }
    function_call = model_msg[:parts].find { |p| p[:functionCall] }
    assert function_call
    assert_equal "read_file", function_call[:functionCall][:name]
  end

  def test_gemini_build_contents_with_tool_call_hashes
    adapter = create_gemini_adapter_for_testing

    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_hash] },
      { role: :tool, results: [{ tool_call_id: "call_123", name: "read_file", content: "file contents" }] }
    ]

    built = adapter.send(:build_contents, messages)

    model_msg = built.find { |m| m[:role] == "model" }
    function_call = model_msg[:parts].find { |p| p[:functionCall] }
    assert function_call
    assert_equal "read_file", function_call[:functionCall][:name]
  end

  def test_gemini_tool_result_gets_name_from_lookup
    adapter = create_gemini_adapter_for_testing

    # Tool result without :name should get it from the preceding tool_call
    messages = [
      { role: :user, content: "Hello" },
      { role: :assistant, content: nil, tool_calls: [@tool_call_object] },
      { role: :tool, results: [{ tool_call_id: "call_123", content: "file contents" }] }  # No :name
    ]

    built = adapter.send(:build_contents, messages)

    # Find the user message with functionResponse (tool results in Gemini)
    tool_result_msg = built.find { |m| m[:role] == "user" && m[:parts]&.any? { |p| p[:functionResponse] } }
    assert tool_result_msg
    function_response = tool_result_msg[:parts].first[:functionResponse]
    assert_equal "read_file", function_response[:name]  # Should be looked up from tool_call
  end

  private

  # Create adapters for testing without requiring API keys
  # We use a fake key since we're only testing message building, not API calls
  def create_openai_adapter_for_testing
    PromptObjects::LLM::OpenAIAdapter.new(api_key: "test-key-not-used")
  end

  def create_anthropic_adapter_for_testing
    PromptObjects::LLM::AnthropicAdapter.new(api_key: "test-key-not-used")
  end

  def create_gemini_adapter_for_testing
    PromptObjects::LLM::GeminiAdapter.new(api_key: "test-key-not-used")
  end
end
