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

  def test_export_delegation_with_child_tool_calls
    # Scenario: solver calls reader, reader does 2 internal tool calls, responds
    parent_id = @store.create_session(po_name: "solver", name: "Root")
    @store.add_message(session_id: parent_id, role: :user, content: "Read and summarize /tmp/data.csv")
    @store.add_message(
      session_id: parent_id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "call_1", name: "reader", arguments: { message: "Read /tmp/data.csv" } }]
    )

    # Reader's delegation thread with its OWN tool loop
    child_id = @store.create_session(
      po_name: "reader",
      name: "Delegation",
      parent_session_id: parent_id,
      parent_po: "solver",
      thread_type: "delegation"
    )
    @store.add_message(session_id: child_id, role: :user, content: "Read /tmp/data.csv", from_po: "solver")
    # Reader calls read_file
    @store.add_message(
      session_id: child_id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "child_call_1", name: "read_file", arguments: { path: "/tmp/data.csv" } }]
    )
    @store.add_message(
      session_id: child_id,
      role: :tool,
      tool_results: [{ tool_call_id: "child_call_1", name: "read_file", content: "name,value\nalpha,42\nbeta,17" }]
    )
    # Reader calls list_files
    @store.add_message(
      session_id: child_id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "child_call_2", name: "list_files", arguments: { path: "/tmp" } }]
    )
    @store.add_message(
      session_id: child_id,
      role: :tool,
      tool_results: [{ tool_call_id: "child_call_2", name: "list_files", content: "data.csv\nother.txt" }]
    )
    # Reader's final response
    @store.add_message(session_id: child_id, role: :assistant, content: "The CSV has 2 rows: alpha=42, beta=17")

    # Back in solver
    @store.add_message(
      session_id: parent_id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "reader", content: "The CSV has 2 rows: alpha=42, beta=17" }]
    )
    @store.add_message(session_id: parent_id, role: :assistant, content: "Summary: the data has 2 entries")

    md = @store.export_thread_tree_markdown(parent_id)

    # Parent section should exist
    assert_includes md, "## solver"
    assert_includes md, "Read and summarize /tmp/data.csv"
    assert_includes md, "Summary: the data has 2 entries"

    # Child section should exist WITH its tool calls
    assert_includes md, "### Delegation → reader"
    assert_includes md, "*Created by solver*"
    # Reader's internal tool calls should be visible
    assert_includes md, "Tool call: <code>read_file</code>"
    assert_includes md, "/tmp/data.csv"
    assert_includes md, "Result from <code>read_file</code>"
    assert_includes md, "name,value"
    assert_includes md, "Tool call: <code>list_files</code>"
    assert_includes md, "Result from <code>list_files</code>"
    assert_includes md, "data.csv"
    # Reader's final response
    assert_includes md, "alpha=42, beta=17"
  end

  def test_export_delegation_renders_inline_after_tool_call
    # The delegation sub-thread should appear right after the tool call,
    # NOT at the bottom after all parent messages
    parent_id = @store.create_session(po_name: "solver", name: "Root")
    @store.add_message(session_id: parent_id, role: :user, content: "Do work")
    @store.add_message(
      session_id: parent_id,
      role: :assistant,
      content: nil,
      tool_calls: [{ id: "call_1", name: "helper", arguments: { message: "Help me" } }]
    )

    child_id = @store.create_session(
      po_name: "helper",
      name: "Delegation",
      parent_session_id: parent_id,
      parent_po: "solver",
      thread_type: "delegation"
    )
    @store.add_message(session_id: child_id, role: :user, content: "Help me", from_po: "solver")
    @store.add_message(session_id: child_id, role: :assistant, content: "Helped!")

    @store.add_message(
      session_id: parent_id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "helper", content: "Helped!" }]
    )
    @store.add_message(session_id: parent_id, role: :assistant, content: "All done")

    md = @store.export_thread_tree_markdown(parent_id)

    # The delegation section should appear BETWEEN the tool call and the tool result
    tool_call_pos = md.index("Tool call: <code>helper</code>")
    delegation_pos = md.index("Delegation → helper")
    result_pos = md.index("Result from <code>helper</code>")
    final_pos = md.index("All done")

    assert tool_call_pos, "Tool call should be in export"
    assert delegation_pos, "Delegation section should be in export"
    assert result_pos, "Tool result should be in export"
    assert final_pos, "Final response should be in export"

    # Delegation should come after tool call but before tool result
    assert tool_call_pos < delegation_pos, "Delegation should come after the tool call"
    assert delegation_pos < result_pos, "Delegation should come before the tool result"
    assert result_pos < final_pos, "Tool result should come before final response"
  end

  def test_export_nonexistent_session
    assert_nil @store.export_thread_tree_markdown("nonexistent")
  end

  def test_export_truncates_long_results
    id = @store.create_session(po_name: "test", name: "Long")
    long_content = "x" * 15_000
    @store.add_message(
      session_id: id,
      role: :tool,
      tool_results: [{ tool_call_id: "call_1", name: "tool", content: long_content }]
    )

    md = @store.export_thread_tree_markdown(id)

    assert_includes md, "... (truncated)"
    # Should have 10000 chars of content, not 15000
    refute_includes md, "x" * 12_000
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
