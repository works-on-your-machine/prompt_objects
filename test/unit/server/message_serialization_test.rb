# frozen_string_literal: true

require_relative "../../test_helper"
require "prompt_objects/server/websocket_handler"

# Tests that message_to_hash correctly handles messages from both
# in-memory history (ToolCall objects) and SQLite (plain Hashes).
# These are the two paths that feed the WebSocket session_updated messages:
#   1. on_history_updated callback → in-memory @history with ToolCall objects
#   2. session_messages → SQLite get_messages → Hashes with symbol keys
#
# A mismatch between these paths caused tool call params to appear initially
# (from callback) then disappear (when SQLite-loaded messages replaced them).
class MessageSerializationTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "serial_test"))
    create_test_po_file(@env_dir, name: "helper", capabilities: ["read_file"])
    @runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)
    @runtime.load_prompt_object(File.join(@env_dir, "objects", "helper.md"))

    # Create a handler we can test message_to_hash on
    @handler = create_test_handler(@runtime)
  end

  # --- Assistant messages with tool calls ---

  def test_tool_calls_from_memory_with_tool_call_objects
    tc = PromptObjects::LLM::ToolCall.new(
      id: "call_abc", name: "read_file", arguments: { "path" => "/tmp/test.txt" }
    )
    msg = { role: :assistant, content: nil, tool_calls: [tc] }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "assistant", result[:role]
    assert_nil result[:content]
    assert_equal 1, result[:tool_calls].length
    assert_equal "call_abc", result[:tool_calls][0][:id]
    assert_equal "read_file", result[:tool_calls][0][:name]
    assert_equal({ "path" => "/tmp/test.txt" }, result[:tool_calls][0][:arguments])
  end

  def test_tool_calls_from_sqlite_with_symbol_key_hashes
    # This is what parse_message_row returns (JSON.parse with symbolize_names)
    msg = {
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "call_abc", name: "read_file", arguments: { path: "/tmp/test.txt" } }]
    }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "assistant", result[:role]
    assert_equal 1, result[:tool_calls].length
    assert_equal "call_abc", result[:tool_calls][0][:id]
    assert_equal "read_file", result[:tool_calls][0][:name]
    assert_equal({ path: "/tmp/test.txt" }, result[:tool_calls][0][:arguments])
  end

  def test_tool_calls_from_sqlite_with_string_key_hashes
    # Edge case: JSON.parse without symbolize_names
    msg = {
      role: :assistant,
      content: nil,
      tool_calls: [{ "id" => "call_abc", "name" => "read_file", "arguments" => { "path" => "/tmp" } }]
    }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "call_abc", result[:tool_calls][0][:id]
    assert_equal "read_file", result[:tool_calls][0][:name]
    assert_equal({ "path" => "/tmp" }, result[:tool_calls][0][:arguments])
  end

  def test_assistant_message_without_tool_calls
    msg = { role: :assistant, content: "Hello!" }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "assistant", result[:role]
    assert_equal "Hello!", result[:content]
    assert_nil result[:tool_calls]
  end

  # --- Tool result messages ---

  def test_tool_results_from_memory
    msg = {
      role: :tool,
      results: [{ tool_call_id: "call_abc", name: "read_file", content: "file contents" }]
    }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "tool", result[:role]
    assert_equal 1, result[:results].length
    assert_equal "call_abc", result[:results][0][:tool_call_id]
  end

  def test_tool_results_from_sqlite
    # SQLite-loaded messages use :tool_results key (from parse_message_row)
    msg = {
      role: :tool,
      tool_results: [{ tool_call_id: "call_abc", name: "read_file", content: "file contents" }]
    }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "tool", result[:role]
    assert_equal 1, result[:results].length
    assert_equal "call_abc", result[:results][0][:tool_call_id]
  end

  def test_tool_results_nil_from_both_keys
    msg = { role: :tool }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "tool", result[:role]
    assert_nil result[:results]
  end

  # --- User messages ---

  def test_user_message_from_memory
    msg = { role: :user, content: "Hello", from: "human" }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "user", result[:role]
    assert_equal "Hello", result[:content]
    assert_equal "human", result[:from]
  end

  def test_user_message_from_sqlite
    # SQLite-loaded messages use :from_po key (from parse_message_row)
    msg = { role: :user, content: "Hello", from_po: "human" }

    result = @handler.send(:message_to_hash, msg)

    assert_equal "user", result[:role]
    assert_equal "Hello", result[:content]
    assert_equal "human", result[:from]
  end

  # --- Full round-trip: persist to SQLite, load back, serialize ---

  def test_full_round_trip_assistant_with_tool_calls
    store = create_memory_store
    session_id = store.create_session(po_name: "helper")

    # Store an assistant message with tool calls (as persist_message does)
    tool_calls_data = [{ id: "call_123", name: "read_file", arguments: { path: "/tmp/test.txt" } }]
    store.add_message(session_id: session_id, role: :assistant, content: nil, tool_calls: tool_calls_data)

    # Load back (as session_messages does)
    messages = store.get_messages(session_id)
    result = @handler.send(:message_to_hash, messages.first)

    assert_equal "assistant", result[:role]
    assert_nil result[:content]
    assert_equal 1, result[:tool_calls].length
    assert_equal "call_123", result[:tool_calls][0][:id]
    assert_equal "read_file", result[:tool_calls][0][:name]
    assert result[:tool_calls][0][:arguments]
  end

  def test_full_round_trip_tool_results
    store = create_memory_store
    session_id = store.create_session(po_name: "helper")

    # Store a tool result message (as persist_message does)
    results = [{ tool_call_id: "call_123", name: "read_file", content: "file contents here" }]
    store.add_message(session_id: session_id, role: :tool, tool_results: results)

    # Load back and serialize
    messages = store.get_messages(session_id)
    result = @handler.send(:message_to_hash, messages.first)

    assert_equal "tool", result[:role]
    assert_equal 1, result[:results].length
    assert_equal "call_123", result[:results][0][:tool_call_id]
    assert_equal "file contents here", result[:results][0][:content]
  end

  def test_full_round_trip_user_message
    store = create_memory_store
    session_id = store.create_session(po_name: "helper")

    store.add_message(session_id: session_id, role: :user, content: "Hello", from_po: "human")

    messages = store.get_messages(session_id)
    result = @handler.send(:message_to_hash, messages.first)

    assert_equal "user", result[:role]
    assert_equal "Hello", result[:content]
    assert_equal "human", result[:from]
  end

  def test_full_round_trip_complete_conversation
    store = create_memory_store
    session_id = store.create_session(po_name: "helper")

    # Simulate a full conversation: user → assistant(tool_call) → tool(result) → assistant(text)
    store.add_message(session_id: session_id, role: :user, content: "Read /tmp/test.txt", from_po: "human")
    store.add_message(
      session_id: session_id, role: :assistant, content: nil,
      tool_calls: [{ id: "call_1", name: "read_file", arguments: { path: "/tmp/test.txt" } }]
    )
    store.add_message(
      session_id: session_id, role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "read_file", content: "Hello World" }]
    )
    store.add_message(session_id: session_id, role: :assistant, content: "The file contains: Hello World")

    # Load and serialize all messages (as the final session_updated does)
    messages = store.get_messages(session_id)
    serialized = messages.map { |m| @handler.send(:message_to_hash, m) }

    assert_equal 4, serialized.length

    # User message
    assert_equal "user", serialized[0][:role]
    assert_equal "Read /tmp/test.txt", serialized[0][:content]
    assert_equal "human", serialized[0][:from]

    # Assistant with tool call
    assert_equal "assistant", serialized[1][:role]
    assert_nil serialized[1][:content]
    assert_equal 1, serialized[1][:tool_calls].length
    assert_equal "call_1", serialized[1][:tool_calls][0][:id]
    assert_equal "read_file", serialized[1][:tool_calls][0][:name]
    assert serialized[1][:tool_calls][0][:arguments], "Tool call arguments must not be nil"

    # Tool result
    assert_equal "tool", serialized[2][:role]
    assert_equal 1, serialized[2][:results].length
    assert_equal "call_1", serialized[2][:results][0][:tool_call_id]
    assert_equal "Hello World", serialized[2][:results][0][:content]

    # Final assistant text
    assert_equal "assistant", serialized[3][:role]
    assert_equal "The file contains: Hello World", serialized[3][:content]
    assert_nil serialized[3][:tool_calls]
  end

  private

  # Create a WebSocketHandler instance for testing private methods.
  # We use a mock connection since we only call message_to_hash.
  def create_test_handler(runtime)
    mock_connection = Object.new
    def mock_connection.write(_data); end
    def mock_connection.flush; end

    PromptObjects::Server::WebSocketHandler.new(
      runtime: runtime,
      connection: mock_connection
    )
  end
end
