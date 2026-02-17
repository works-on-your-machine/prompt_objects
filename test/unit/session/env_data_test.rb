# frozen_string_literal: true

require_relative "../../test_helper"

class EnvDataStoreTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
  end

  # --- Store and Retrieve ---

  def test_store_and_get_env_data
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "arc_task",
      short_description: "Current ARC puzzle: training-001",
      value: { task_id: "training-001", grid: [[1, 2], [3, 4]] },
      stored_by: "solver"
    )

    entry = @store.get_env_data(root_thread_id: root_id, key: "arc_task")

    assert entry
    assert_equal "arc_task", entry[:key]
    assert_equal "Current ARC puzzle: training-001", entry[:short_description]
    assert_equal({ task_id: "training-001", grid: [[1, 2], [3, 4]] }, entry[:value])
    assert_equal "solver", entry[:stored_by]
  end

  def test_store_overwrites_existing_key
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "findings",
      short_description: "Initial findings",
      value: ["pattern_a"],
      stored_by: "observer"
    )

    @store.store_env_data(
      root_thread_id: root_id,
      key: "findings",
      short_description: "Updated findings with more patterns",
      value: ["pattern_a", "pattern_b"],
      stored_by: "observer"
    )

    entry = @store.get_env_data(root_thread_id: root_id, key: "findings")
    assert_equal "Updated findings with more patterns", entry[:short_description]
    assert_equal ["pattern_a", "pattern_b"], entry[:value]
  end

  def test_get_returns_nil_for_unknown_key
    root_id = @store.create_session(po_name: "coordinator")

    entry = @store.get_env_data(root_thread_id: root_id, key: "nonexistent")
    assert_nil entry
  end

  # --- List ---

  def test_list_returns_keys_and_descriptions_without_values
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "arc_task",
      short_description: "The current puzzle",
      value: { big: "data" },
      stored_by: "solver"
    )

    @store.store_env_data(
      root_thread_id: root_id,
      key: "findings",
      short_description: "Observed patterns",
      value: ["lots", "of", "patterns"],
      stored_by: "observer"
    )

    entries = @store.list_env_data(root_thread_id: root_id)

    assert_equal 2, entries.size
    # Sorted by key ASC
    assert_equal "arc_task", entries[0][:key]
    assert_equal "The current puzzle", entries[0][:short_description]
    assert_nil entries[0][:value]

    assert_equal "findings", entries[1][:key]
    assert_equal "Observed patterns", entries[1][:short_description]
    assert_nil entries[1][:value]
  end

  def test_list_returns_empty_array_when_no_data
    root_id = @store.create_session(po_name: "coordinator")

    entries = @store.list_env_data(root_thread_id: root_id)
    assert_equal [], entries
  end

  # --- Update ---

  def test_update_existing_key
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "findings",
      short_description: "Initial findings",
      value: ["pattern_a"],
      stored_by: "observer"
    )

    result = @store.update_env_data(
      root_thread_id: root_id,
      key: "findings",
      short_description: "Updated: 2 patterns found",
      value: ["pattern_a", "pattern_b"],
      stored_by: "observer"
    )

    assert result

    entry = @store.get_env_data(root_thread_id: root_id, key: "findings")
    assert_equal "Updated: 2 patterns found", entry[:short_description]
    assert_equal ["pattern_a", "pattern_b"], entry[:value]
  end

  def test_update_value_only
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "count",
      short_description: "Running count",
      value: 1,
      stored_by: "counter"
    )

    @store.update_env_data(
      root_thread_id: root_id,
      key: "count",
      value: 2,
      stored_by: "counter"
    )

    entry = @store.get_env_data(root_thread_id: root_id, key: "count")
    assert_equal "Running count", entry[:short_description]
    assert_equal 2, entry[:value]
  end

  def test_update_nonexistent_key_returns_false
    root_id = @store.create_session(po_name: "coordinator")

    result = @store.update_env_data(
      root_thread_id: root_id,
      key: "nonexistent",
      value: "something",
      stored_by: "test"
    )

    refute result
  end

  # --- Delete ---

  def test_delete_existing_key
    root_id = @store.create_session(po_name: "coordinator")

    @store.store_env_data(
      root_thread_id: root_id,
      key: "temp_data",
      short_description: "Temporary data",
      value: "will be deleted",
      stored_by: "test"
    )

    result = @store.delete_env_data(root_thread_id: root_id, key: "temp_data")
    assert result

    entry = @store.get_env_data(root_thread_id: root_id, key: "temp_data")
    assert_nil entry
  end

  def test_delete_nonexistent_key_returns_false
    root_id = @store.create_session(po_name: "coordinator")

    result = @store.delete_env_data(root_thread_id: root_id, key: "nonexistent")
    refute result
  end

  # --- Root Thread Resolution ---

  def test_resolve_root_thread_with_delegation_chain
    root_id = @store.create_session(po_name: "coordinator")
    child_id = @store.create_session(
      po_name: "solver",
      parent_session_id: root_id,
      parent_po: "coordinator",
      thread_type: "delegation"
    )
    grandchild_id = @store.create_session(
      po_name: "observer",
      parent_session_id: child_id,
      parent_po: "solver",
      thread_type: "delegation"
    )

    assert_equal root_id, @store.resolve_root_thread(grandchild_id)
    assert_equal root_id, @store.resolve_root_thread(child_id)
    assert_equal root_id, @store.resolve_root_thread(root_id)
  end

  def test_resolve_root_thread_returns_self_when_no_parent
    root_id = @store.create_session(po_name: "standalone")

    assert_equal root_id, @store.resolve_root_thread(root_id)
  end

  # --- Thread Scoping Isolation ---

  def test_data_from_one_root_invisible_to_another
    root_a = @store.create_session(po_name: "coordinator_a")
    root_b = @store.create_session(po_name: "coordinator_b")

    @store.store_env_data(
      root_thread_id: root_a,
      key: "task",
      short_description: "Task A data",
      value: "data_a",
      stored_by: "solver"
    )

    @store.store_env_data(
      root_thread_id: root_b,
      key: "task",
      short_description: "Task B data",
      value: "data_b",
      stored_by: "solver"
    )

    entry_a = @store.get_env_data(root_thread_id: root_a, key: "task")
    entry_b = @store.get_env_data(root_thread_id: root_b, key: "task")

    assert_equal "data_a", entry_a[:value]
    assert_equal "data_b", entry_b[:value]

    list_a = @store.list_env_data(root_thread_id: root_a)
    list_b = @store.list_env_data(root_thread_id: root_b)

    assert_equal 1, list_a.size
    assert_equal 1, list_b.size
    assert_equal "Task A data", list_a[0][:short_description]
    assert_equal "Task B data", list_b[0][:short_description]
  end

  # --- Value Serialization ---

  def test_stores_string_values
    root_id = @store.create_session(po_name: "test")
    @store.store_env_data(root_thread_id: root_id, key: "msg", short_description: "A message", value: "hello world", stored_by: "test")

    entry = @store.get_env_data(root_thread_id: root_id, key: "msg")
    assert_equal "hello world", entry[:value]
  end

  def test_stores_numeric_values
    root_id = @store.create_session(po_name: "test")
    @store.store_env_data(root_thread_id: root_id, key: "count", short_description: "A count", value: 42, stored_by: "test")

    entry = @store.get_env_data(root_thread_id: root_id, key: "count")
    assert_equal 42, entry[:value]
  end

  def test_stores_nested_hash_values
    root_id = @store.create_session(po_name: "test")
    value = { grid: [[1, 2], [3, 4]], metadata: { size: 2 } }
    @store.store_env_data(root_thread_id: root_id, key: "complex", short_description: "Complex data", value: value, stored_by: "test")

    entry = @store.get_env_data(root_thread_id: root_id, key: "complex")
    assert_equal({ grid: [[1, 2], [3, 4]], metadata: { size: 2 } }, entry[:value])
  end
end
