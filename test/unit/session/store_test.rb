# frozen_string_literal: true

require_relative "../../test_helper"

class SessionStoreTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
  end

  # --- Session CRUD ---

  def test_create_session_returns_id
    id = @store.create_session(po_name: "test_po", name: "Test Session")

    assert id
    assert_kind_of String, id
    assert_match(/\A[a-f0-9-]{36}\z/, id) # UUID format
  end

  def test_create_session_with_source
    id = @store.create_session(po_name: "test_po", name: "MCP Session", source: "mcp")

    session = @store.get_session(id)
    assert_equal "mcp", session[:source]
  end

  def test_create_session_defaults_to_tui_source
    id = @store.create_session(po_name: "test_po", name: "Test")

    session = @store.get_session(id)
    assert_equal "tui", session[:source]
  end

  def test_get_session_returns_session_data
    id = @store.create_session(po_name: "test_po", name: "Test Session")

    session = @store.get_session(id)

    assert_equal id, session[:id]
    assert_equal "test_po", session[:po_name]
    assert_equal "Test Session", session[:name]
    assert_kind_of Time, session[:created_at]
    assert_kind_of Time, session[:updated_at]
  end

  def test_get_session_returns_nil_for_unknown_id
    session = @store.get_session("nonexistent-id")

    assert_nil session
  end

  def test_get_or_create_session_creates_new
    session = @store.get_or_create_session(po_name: "new_po")

    assert session[:id]
    assert_equal "new_po", session[:po_name]
  end

  def test_get_or_create_session_returns_existing
    id = @store.create_session(po_name: "test_po", name: "Existing")

    session = @store.get_or_create_session(po_name: "test_po")

    assert_equal id, session[:id]
  end

  def test_update_session_name
    id = @store.create_session(po_name: "test_po", name: "Original")

    @store.update_session(id, name: "Updated")
    session = @store.get_session(id)

    assert_equal "Updated", session[:name]
  end

  def test_update_session_last_message_source
    id = @store.create_session(po_name: "test_po", name: "Test")

    @store.update_session(id, last_message_source: "mcp")
    session = @store.get_session(id)

    assert_equal "mcp", session[:last_message_source]
  end

  def test_update_session_with_all_parameters
    id = @store.create_session(po_name: "test_po", name: "Original")

    @store.update_session(id,
      name: "Updated",
      last_message_source: "api",
      metadata: { key: "value" }
    )

    session = @store.get_session(id)
    assert_equal "Updated", session[:name]
    assert_equal "api", session[:last_message_source]
    # Metadata comes back with symbol keys
    assert_equal({ key: "value" }, session[:metadata])
  end

  def test_delete_session
    id = @store.create_session(po_name: "test_po", name: "To Delete")
    @store.add_message(session_id: id, role: :user, content: "Test message")

    @store.delete_session(id)

    assert_nil @store.get_session(id)
    assert_empty @store.get_messages(id)
  end

  def test_list_sessions_by_po_name
    @store.create_session(po_name: "po1", name: "Session 1")
    @store.create_session(po_name: "po1", name: "Session 2")
    @store.create_session(po_name: "po2", name: "Session 3")

    sessions = @store.list_sessions(po_name: "po1")

    assert_equal 2, sessions.length
    assert sessions.all? { |s| s[:po_name] == "po1" }
  end

  def test_list_all_sessions
    @store.create_session(po_name: "po1", name: "Session 1")
    @store.create_session(po_name: "po2", name: "Session 2")

    sessions = @store.list_all_sessions

    assert_equal 2, sessions.length
  end

  def test_list_all_sessions_with_source_filter
    @store.create_session(po_name: "po1", name: "TUI Session", source: "tui")
    @store.create_session(po_name: "po1", name: "MCP Session", source: "mcp")

    tui_sessions = @store.list_all_sessions(source: "tui")
    mcp_sessions = @store.list_all_sessions(source: "mcp")

    assert_equal 1, tui_sessions.length
    assert_equal "TUI Session", tui_sessions.first[:name]
    assert_equal 1, mcp_sessions.length
    assert_equal "MCP Session", mcp_sessions.first[:name]
  end

  # --- Message CRUD ---

  def test_add_message_user
    id = @store.create_session(po_name: "test_po", name: "Test")

    msg_id = @store.add_message(session_id: id, role: :user, content: "Hello")

    assert msg_id
    messages = @store.get_messages(id)
    assert_equal 1, messages.length
    assert_equal :user, messages.first[:role]
    assert_equal "Hello", messages.first[:content]
  end

  def test_add_message_assistant_with_tool_calls
    id = @store.create_session(po_name: "test_po", name: "Test")

    tool_calls = [{ id: "call_123", name: "read_file", arguments: { path: "/tmp" } }]
    @store.add_message(session_id: id, role: :assistant, content: nil, tool_calls: tool_calls)

    messages = @store.get_messages(id)
    assert_equal 1, messages.length
    assert_equal :assistant, messages.first[:role]
    assert_equal tool_calls, messages.first[:tool_calls]
  end

  def test_add_message_tool_results
    id = @store.create_session(po_name: "test_po", name: "Test")

    results = [{ tool_call_id: "call_123", content: "file contents" }]
    @store.add_message(session_id: id, role: :tool, tool_results: results)

    messages = @store.get_messages(id)
    assert_equal 1, messages.length
    assert_equal :tool, messages.first[:role]
    assert_equal results, messages.first[:tool_results]
  end

  def test_add_message_updates_session_timestamp
    id = @store.create_session(po_name: "test_po", name: "Test")
    original_session = @store.get_session(id)
    original_time = original_session[:updated_at]

    sleep 0.01 # Ensure time difference
    @store.add_message(session_id: id, role: :user, content: "Hello")

    updated_session = @store.get_session(id)
    assert updated_session[:updated_at] >= original_time
  end

  def test_add_message_with_source_updates_last_message_source
    id = @store.create_session(po_name: "test_po", name: "Test")

    @store.add_message(session_id: id, role: :user, content: "Hello", source: "mcp")

    session = @store.get_session(id)
    assert_equal "mcp", session[:last_message_source]
  end

  def test_message_count
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "One")
    @store.add_message(session_id: id, role: :assistant, content: "Two")
    @store.add_message(session_id: id, role: :user, content: "Three")

    count = @store.message_count(id)

    assert_equal 3, count
  end

  def test_clear_messages
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello")
    @store.add_message(session_id: id, role: :assistant, content: "Hi")

    @store.clear_messages(id)

    assert_equal 0, @store.message_count(id)
  end

  # --- Search (FTS) ---

  def test_search_sessions_finds_matching_content
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello world, this is a test")

    results = @store.search_sessions("hello")

    assert_equal 1, results.length
    assert_equal id, results.first[:id]
  end

  def test_search_sessions_returns_empty_for_no_match
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello world")

    results = @store.search_sessions("nonexistent")

    assert_empty results
  end

  def test_search_sessions_with_source_filter
    id1 = @store.create_session(po_name: "test_po", name: "TUI", source: "tui")
    id2 = @store.create_session(po_name: "test_po", name: "MCP", source: "mcp")
    @store.add_message(session_id: id1, role: :user, content: "searchterm in tui")
    @store.add_message(session_id: id2, role: :user, content: "searchterm in mcp")

    tui_results = @store.search_sessions("searchterm", source: "tui")
    mcp_results = @store.search_sessions("searchterm", source: "mcp")

    assert_equal 1, tui_results.length
    assert_equal "tui", tui_results.first[:source]
    assert_equal 1, mcp_results.length
    assert_equal "mcp", mcp_results.first[:source]
  end

  def test_search_sessions_returns_empty_for_empty_query
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello world")

    results = @store.search_sessions("")

    assert_empty results
  end

  def test_search_sessions_returns_empty_for_nil_query
    id = @store.create_session(po_name: "test_po", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello world")

    results = @store.search_sessions(nil)

    assert_empty results
  end

  # --- Export/Import ---

  def test_export_session_json
    id = @store.create_session(po_name: "test_po", name: "Export Test")
    @store.add_message(session_id: id, role: :user, content: "Hello")
    @store.add_message(session_id: id, role: :assistant, content: "Hi there")

    data = @store.export_session_json(id)

    # Export returns flat structure with session fields and messages array
    assert_equal id, data[:id]
    assert_equal "test_po", data[:po_name]
    assert_equal 2, data[:messages].length
  end

  def test_export_session_markdown
    id = @store.create_session(po_name: "test_po", name: "Export Test")
    @store.add_message(session_id: id, role: :user, content: "Hello")
    @store.add_message(session_id: id, role: :assistant, content: "Hi there")

    markdown = @store.export_session_markdown(id)

    assert_includes markdown, "# Session: Export Test"
    assert_includes markdown, "**User**"  # Capitalized
    assert_includes markdown, "Hello"
    assert_includes markdown, "**test_po**"  # Uses PO name for assistant
    assert_includes markdown, "Hi there"
  end

  def test_import_session
    # Create and export a session
    id = @store.create_session(po_name: "test_po", name: "Import Test")
    @store.add_message(session_id: id, role: :user, content: "Original message")
    data = @store.export_session_json(id)

    # Delete it
    @store.delete_session(id)
    assert_nil @store.get_session(id)

    # Import it back
    new_id = @store.import_session(data)

    assert new_id
    session = @store.get_session(new_id)
    assert_equal "test_po", session[:po_name]
    # Import adds "(imported)" suffix
    assert_includes session[:name], "Import Test"

    messages = @store.get_messages(new_id)
    assert_equal 1, messages.length
    assert_equal "Original message", messages.first[:content]
  end

  # --- Stats ---

  def test_total_sessions
    @store.create_session(po_name: "po1", name: "S1")
    @store.create_session(po_name: "po2", name: "S2")

    assert_equal 2, @store.total_sessions
  end

  def test_total_messages
    id1 = @store.create_session(po_name: "po1", name: "S1")
    id2 = @store.create_session(po_name: "po2", name: "S2")
    @store.add_message(session_id: id1, role: :user, content: "M1")
    @store.add_message(session_id: id1, role: :assistant, content: "M2")
    @store.add_message(session_id: id2, role: :user, content: "M3")

    assert_equal 3, @store.total_messages
  end
end
