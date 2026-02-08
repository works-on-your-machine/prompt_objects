# frozen_string_literal: true

require_relative "../../test_helper"

class SessionUsageTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
  end

  def test_session_usage_with_no_messages
    id = @store.create_session(po_name: "test", name: "Empty")
    usage = @store.session_usage(id)

    assert_equal 0, usage[:input_tokens]
    assert_equal 0, usage[:output_tokens]
    assert_equal 0, usage[:total_tokens]
    assert_equal 0.0, usage[:estimated_cost_usd]
    assert_equal 0, usage[:calls]
    assert_empty usage[:by_model]
  end

  def test_session_usage_with_no_usage_data
    id = @store.create_session(po_name: "test", name: "NoUsage")
    @store.add_message(session_id: id, role: :user, content: "Hello")
    @store.add_message(session_id: id, role: :assistant, content: "Hi")

    usage = @store.session_usage(id)

    assert_equal 0, usage[:calls]
    assert_equal 0, usage[:input_tokens]
  end

  def test_session_usage_single_call
    id = @store.create_session(po_name: "test", name: "Single")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Hello",
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )

    usage = @store.session_usage(id)

    assert_equal 100, usage[:input_tokens]
    assert_equal 50, usage[:output_tokens]
    assert_equal 150, usage[:total_tokens]
    assert_equal 1, usage[:calls]
    assert usage[:estimated_cost_usd] > 0
    assert_equal 1, usage[:by_model]["gpt-4.1"][:calls]
  end

  def test_session_usage_multiple_calls
    id = @store.create_session(po_name: "test", name: "Multi")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: nil,
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Done",
      usage: { input_tokens: 200, output_tokens: 100, model: "gpt-4.1" }
    )

    usage = @store.session_usage(id)

    assert_equal 300, usage[:input_tokens]
    assert_equal 150, usage[:output_tokens]
    assert_equal 450, usage[:total_tokens]
    assert_equal 2, usage[:calls]
    assert_equal 2, usage[:by_model]["gpt-4.1"][:calls]
  end

  def test_session_usage_mixed_models
    id = @store.create_session(po_name: "test", name: "Mixed")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "GPT response",
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Claude response",
      usage: { input_tokens: 200, output_tokens: 80, model: "claude-sonnet-4-5" }
    )

    usage = @store.session_usage(id)

    assert_equal 300, usage[:input_tokens]
    assert_equal 130, usage[:output_tokens]
    assert_equal 2, usage[:calls]
    assert_equal 2, usage[:by_model].size
    assert_equal 1, usage[:by_model]["gpt-4.1"][:calls]
    assert_equal 1, usage[:by_model]["claude-sonnet-4-5"][:calls]
  end

  def test_session_usage_unknown_model
    id = @store.create_session(po_name: "test", name: "Unknown")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Response",
      usage: { input_tokens: 500, output_tokens: 200, model: "local-model" }
    )

    usage = @store.session_usage(id)

    assert_equal 500, usage[:input_tokens]
    assert_equal 200, usage[:output_tokens]
    assert_equal 1, usage[:calls]
    # Unknown model = $0 cost
    assert_equal 0.0, usage[:estimated_cost_usd]
    assert_equal 1, usage[:by_model]["local-model"][:calls]
  end

  def test_thread_tree_usage_single_session
    id = @store.create_session(po_name: "test", name: "Root")
    @store.add_message(
      session_id: id,
      role: :assistant,
      content: "Hi",
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )

    usage = @store.thread_tree_usage(id)

    assert_equal 100, usage[:input_tokens]
    assert_equal 50, usage[:output_tokens]
    assert_equal 1, usage[:calls]
  end

  def test_thread_tree_usage_with_children
    parent_id = @store.create_session(po_name: "test", name: "Root")
    @store.add_message(
      session_id: parent_id,
      role: :assistant,
      content: "Parent response",
      usage: { input_tokens: 100, output_tokens: 50, model: "gpt-4.1" }
    )

    child_id = @store.create_session(
      po_name: "helper",
      name: "Delegation",
      parent_session_id: parent_id,
      parent_po: "test",
      thread_type: "delegation"
    )
    @store.add_message(
      session_id: child_id,
      role: :assistant,
      content: "Child response",
      usage: { input_tokens: 200, output_tokens: 80, model: "claude-sonnet-4-5" }
    )

    usage = @store.thread_tree_usage(parent_id)

    assert_equal 300, usage[:input_tokens]
    assert_equal 130, usage[:output_tokens]
    assert_equal 430, usage[:total_tokens]
    assert_equal 2, usage[:calls]
    assert_equal 2, usage[:by_model].size
  end

  def test_thread_tree_usage_nonexistent_session
    usage = @store.thread_tree_usage("nonexistent-id")

    assert_equal 0, usage[:input_tokens]
    assert_equal 0, usage[:calls]
  end
end
