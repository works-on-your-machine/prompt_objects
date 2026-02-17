# frozen_string_literal: true

require_relative "../../test_helper"

class MCPToolsTest < PromptObjectsTest
  def setup
    super
    @temp_dir = track_temp_dir(create_temp_env(name: "mcp_test"))

    # Create test POs
    create_test_po_file(@temp_dir, name: "greeter", description: "A friendly greeter", capabilities: ["read_file"])
    create_test_po_file(@temp_dir, name: "helper", description: "A helpful assistant", capabilities: [])

    @runtime = PromptObjects::Runtime.new(env_path: @temp_dir, llm: MockLLM.new)

    # Load the POs
    Dir.glob(File.join(@temp_dir, "objects", "*.md")).each do |path|
      @runtime.load_prompt_object(path)
    end

    @connector = MockConnector.new(runtime: @runtime)
    @ctx = create_mcp_context(@runtime, connector: @connector)
  end

  # --- ListPromptObjects ---

  def test_list_prompt_objects_returns_all_pos
    result = PromptObjects::Connectors::MCP::Tools::ListPromptObjects.call(server_context: @ctx)

    assert_kind_of ::MCP::Tool::Response, result
    data = JSON.parse(result.content.first[:text])

    assert_equal 2, data["prompt_objects"].length
    names = data["prompt_objects"].map { |po| po["name"] }
    assert_includes names, "greeter"
    assert_includes names, "helper"
  end

  def test_list_prompt_objects_includes_required_fields
    result = PromptObjects::Connectors::MCP::Tools::ListPromptObjects.call(server_context: @ctx)
    data = JSON.parse(result.content.first[:text])

    po = data["prompt_objects"].first
    assert po.key?("name"), "Should include name"
    assert po.key?("description"), "Should include description"
    assert po.key?("status"), "Should include status"
    assert po.key?("capabilities"), "Should include capabilities"
  end

  def test_list_prompt_objects_capabilities_is_array
    result = PromptObjects::Connectors::MCP::Tools::ListPromptObjects.call(server_context: @ctx)
    data = JSON.parse(result.content.first[:text])

    greeter = data["prompt_objects"].find { |po| po["name"] == "greeter" }
    assert_kind_of Array, greeter["capabilities"]
    cap_names = greeter["capabilities"].map { |c| c["name"] }
    assert_includes cap_names, "read_file"
  end

  # --- SendMessage ---

  def test_send_message_to_valid_po
    result = PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["response"], "Should include response"
    assert_equal "greeter", data["po_name"]
  end

  def test_send_message_to_invalid_po_returns_error
    result = PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "nonexistent",
      message: "Hello!",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["error"]
    assert_includes data["error"], "not found"
  end

  def test_send_message_creates_session_if_none_exists
    po = @runtime.registry.get("greeter")
    po.instance_variable_set(:@session_id, nil) # Clear any existing session

    result = PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["session_id"], "Should return a session ID"
  end

  def test_send_message_uses_existing_session
    po = @runtime.registry.get("greeter")
    existing_session_id = po.instance_variable_get(:@session_id)

    result = PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert_equal existing_session_id, data["session_id"]
  end

  def test_send_message_includes_history_length
    result = PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data.key?("history_length")
    assert_kind_of Integer, data["history_length"]
  end

  # --- GetConversation ---

  def test_get_conversation_for_valid_po
    # Send a message first to create history
    PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    result = PromptObjects::Connectors::MCP::Tools::GetConversation.call(
      po_name: "greeter",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["history"], "Should include history"
    assert_kind_of Array, data["history"]
    assert data["history"].length > 0
  end

  def test_get_conversation_for_invalid_po_returns_error
    result = PromptObjects::Connectors::MCP::Tools::GetConversation.call(
      po_name: "nonexistent",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["error"]
  end

  # --- ListSessions ---

  def test_list_sessions_returns_all_sessions
    # Create a session by sending a message
    PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    result = PromptObjects::Connectors::MCP::Tools::ListSessions.call(server_context: @ctx)

    data = JSON.parse(result.content.first[:text])
    assert data["sessions"], "Should include sessions"
    assert data["sessions"].length >= 1
  end

  def test_list_sessions_filters_by_po_name
    # Ensure both POs have sessions
    PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello greeter!",
      server_context: @ctx
    )
    PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "helper",
      message: "Hello helper!",
      server_context: @ctx
    )

    result = PromptObjects::Connectors::MCP::Tools::ListSessions.call(
      po_name: "greeter",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["sessions"].all? { |s| s["po_name"] == "greeter" }
  end

  def test_list_sessions_includes_required_fields
    PromptObjects::Connectors::MCP::Tools::SendMessage.call(
      po_name: "greeter",
      message: "Hello!",
      server_context: @ctx
    )

    result = PromptObjects::Connectors::MCP::Tools::ListSessions.call(server_context: @ctx)

    data = JSON.parse(result.content.first[:text])
    session = data["sessions"].first

    assert session.key?("id")
    assert session.key?("po_name")
    assert session.key?("name")
    assert session.key?("source")
    assert session.key?("message_count")
  end

  # --- InspectPO ---

  def test_inspect_po_returns_details
    result = PromptObjects::Connectors::MCP::Tools::InspectPO.call(
      po_name: "greeter",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert_equal "greeter", data["name"]
    assert_equal "A friendly greeter", data["description"]
    assert data.key?("prompt")
    assert data.key?("capabilities")
    assert data.key?("config")
  end

  def test_inspect_po_invalid_returns_error
    result = PromptObjects::Connectors::MCP::Tools::InspectPO.call(
      po_name: "nonexistent",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["error"]
  end

  # --- GetPendingRequests ---

  def test_get_pending_requests_returns_array
    result = PromptObjects::Connectors::MCP::Tools::GetPendingRequests.call(server_context: @ctx)

    data = JSON.parse(result.content.first[:text])
    assert data.key?("pending_requests")
    assert_kind_of Array, data["pending_requests"]
  end

  # --- RespondToRequest ---

  def test_respond_to_request_with_invalid_id_returns_error
    result = PromptObjects::Connectors::MCP::Tools::RespondToRequest.call(
      request_id: "nonexistent",
      response: "test response",
      server_context: @ctx
    )

    data = JSON.parse(result.content.first[:text])
    assert data["error"]
  end
end
