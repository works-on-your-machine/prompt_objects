# frozen_string_literal: true

require_relative "../../test_helper"

class SessionExportTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
  end

  # --- Markdown tree export ---

  def test_export_single_session_markdown
    id = @store.create_session(po_name: "solver", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello")
    @store.add_message(session_id: id, role: :assistant, content: "Hi there")

    md = @store.export_thread_tree_markdown(id)

    assert_includes md, "# Thread Export"
    assert_includes md, "**Root PO**: solver"
    assert_includes md, "## solver"
    assert_includes md, "**human:**"
    assert_includes md, "Hello"
    assert_includes md, "**solver:**"
    assert_includes md, "Hi there"
  end

  def test_export_with_tool_calls
    id = @store.create_session(po_name: "solver", name: "Tools")
    @store.add_message(session_id: id, role: :user, content: "Read a file")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "call_1", name: "read_file", arguments: { path: "/tmp/test.txt" } }]
    )
    @store.add_message(
      session_id: id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "read_file", content: "file contents here" }]
    )
    @store.add_message(session_id: id, role: :assistant, content: "The file says: file contents here")

    md = @store.export_thread_tree_markdown(id)

    assert_includes md, "Tool call: <code>read_file</code>"
    assert_includes md, "/tmp/test.txt"
    assert_includes md, "Result from <code>read_file</code>"
    assert_includes md, "file contents here"
    assert_includes md, "The file says"
  end

  def test_export_with_delegation_child
    parent_id = @store.create_session(po_name: "solver", name: "Root")
    @store.add_message(session_id: parent_id, role: :user, content: "Analyze this")
    @store.add_message(
      session_id: parent_id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "call_1", name: "reader", arguments: { message: "Read /tmp/data" } }]
    )

    child_id = @store.create_session(
      po_name: "reader",
      name: "Delegation",
      parent_session_id: parent_id,
      parent_po: "solver",
      thread_type: "delegation"
    )
    @store.add_message(session_id: child_id, role: :user, content: "Read /tmp/data", from_po: "solver")
    @store.add_message(session_id: child_id, role: :assistant, content: "Data contents: 1,2,3")

    @store.add_message(
      session_id: parent_id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "reader", content: "Data contents: 1,2,3" }]
    )
    @store.add_message(session_id: parent_id, role: :assistant, content: "Analysis complete")

    md = @store.export_thread_tree_markdown(parent_id)

    assert_includes md, "## solver"
    assert_includes md, "### Delegation → reader"
    assert_includes md, "*Created by solver*"
    assert_includes md, "**reader:**"
    assert_includes md, "Data contents: 1,2,3"
    assert_includes md, "Analysis complete"
  end

  def test_export_with_nested_delegations
    root_id = @store.create_session(po_name: "orchestrator", name: "Root")
    @store.add_message(session_id: root_id, role: :user, content: "Do the thing")

    mid_id = @store.create_session(
      po_name: "worker",
      name: "Mid",
      parent_session_id: root_id,
      parent_po: "orchestrator",
      thread_type: "delegation"
    )
    @store.add_message(session_id: mid_id, role: :user, content: "Step 1", from_po: "orchestrator")

    leaf_id = @store.create_session(
      po_name: "helper",
      name: "Leaf",
      parent_session_id: mid_id,
      parent_po: "worker",
      thread_type: "delegation"
    )
    @store.add_message(session_id: leaf_id, role: :user, content: "Sub-step", from_po: "worker")
    @store.add_message(session_id: leaf_id, role: :assistant, content: "Done")

    md = @store.export_thread_tree_markdown(root_id)

    assert_includes md, "## orchestrator"
    assert_includes md, "### Delegation → worker"
    assert_includes md, "### Delegation → helper"
    assert_includes md, "*Created by worker*"
  end

  def test_export_nonexistent_session
    assert_nil @store.export_thread_tree_markdown("nonexistent")
  end

  def test_export_truncates_long_results
    id = @store.create_session(po_name: "test", name: "Long")
    long_content = "x" * 3000
    @store.add_message(
      session_id: id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "tool", content: long_content }]
    )

    md = @store.export_thread_tree_markdown(id)

    assert_includes md, "... (truncated)"
    # Should have 2000 chars of content, not 3000
    refute_includes md, "x" * 2500
  end

  # --- JSON tree export ---

  def test_export_json_single_session
    id = @store.create_session(po_name: "solver", name: "Test")
    @store.add_message(session_id: id, role: :user, content: "Hello")

    data = @store.export_thread_tree_json(id)

    assert_equal "solver", data[:session][:po_name]
    assert_equal 1, data[:messages].length
    assert_equal "user", data[:messages].first[:role]
    assert_empty data[:children]
  end

  def test_export_json_with_children
    parent_id = @store.create_session(po_name: "solver", name: "Root")
    @store.add_message(session_id: parent_id, role: :user, content: "Go")

    child_id = @store.create_session(
      po_name: "helper",
      name: "Child",
      parent_session_id: parent_id,
      parent_po: "solver",
      thread_type: "delegation"
    )
    @store.add_message(session_id: child_id, role: :user, content: "Sub-task")

    data = @store.export_thread_tree_json(parent_id)

    assert_equal 1, data[:children].length
    assert_equal "helper", data[:children].first[:session][:po_name]
    assert_equal "delegation", data[:children].first[:session][:thread_type]
    assert_equal 1, data[:children].first[:messages].length
  end

  def test_export_json_nonexistent_session
    assert_nil @store.export_thread_tree_json("nonexistent")
  end

  def test_export_json_includes_usage
    id = @store.create_session(po_name: "test", name: "Usage")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Hi",
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )

    data = @store.export_thread_tree_json(id)

    msg = data[:messages].first
    assert msg[:usage]
    assert_equal 100, msg[:usage][:input_tokens]
  end
end
