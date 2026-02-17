# frozen_string_literal: true

require_relative "../../test_helper"

class UniversalEnvDataTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
    @root_id = @store.create_session(po_name: "coordinator")

    # Create a mock PO with a session_id
    @mock_po = Struct.new(:session_id).new(@root_id)

    # Create a mock registry that returns our mock PO
    @mock_registry = Object.new
    def @mock_registry.get(name)
      @po_map ||= {}
      @po_map[name]
    end
    def @mock_registry.set(name, po)
      @po_map ||= {}
      @po_map[name] = po
    end
    @mock_registry.set("solver", @mock_po)

    # Create a mock env
    @mock_env = Struct.new(:session_store, :registry).new(@store, @mock_registry)
    def @mock_env.notify_env_data_changed(**kwargs); end

    # Create a mock bus that records publishes
    @mock_bus = Object.new
    def @mock_bus.publishes; @publishes ||= []; end
    def @mock_bus.publish(**kwargs); publishes << kwargs; end

    # Build context
    @context = PromptObjects::Context.new(env: @mock_env, bus: @mock_bus)
    @context.calling_po = "solver"
  end

  # --- store_env_data ---

  def test_store_env_data_stores_value
    cap = PromptObjects::Universal::StoreEnvData.new
    result = cap.receive(
      { key: "task", short_description: "The task", value: { id: 1 } },
      context: @context
    )

    assert_equal "Stored 'task' in environment data.", result

    entry = @store.get_env_data(root_thread_id: @root_id, key: "task")
    assert entry
    assert_equal({ id: 1 }, entry[:value])
  end

  def test_store_env_data_publishes_to_bus
    cap = PromptObjects::Universal::StoreEnvData.new
    cap.receive(
      { key: "task", short_description: "The task", value: "data" },
      context: @context
    )

    assert_equal 1, @mock_bus.publishes.size
    msg = @mock_bus.publishes.first
    assert_equal "solver", msg[:from]
    assert_equal "env_data", msg[:to]
    assert_equal "store", msg[:message][:action]
    assert_equal "task", msg[:message][:key]
  end

  def test_store_env_data_error_without_key
    cap = PromptObjects::Universal::StoreEnvData.new
    result = cap.receive(
      { short_description: "desc", value: "data" },
      context: @context
    )

    assert_match(/key.*required/i, result)
  end

  # --- get_env_data ---

  def test_get_env_data_retrieves_value
    @store.store_env_data(
      root_thread_id: @root_id, key: "task",
      short_description: "The task", value: { id: 1 }, stored_by: "solver"
    )

    cap = PromptObjects::Universal::GetEnvData.new
    result = cap.receive({ key: "task" }, context: @context)

    parsed = JSON.parse(result, symbolize_names: true)
    assert_equal({ id: 1 }, parsed)
  end

  def test_get_env_data_not_found
    cap = PromptObjects::Universal::GetEnvData.new
    result = cap.receive({ key: "nonexistent" }, context: @context)

    assert_match(/not found/, result)
  end

  # --- list_env_data ---

  def test_list_env_data_returns_keys_and_descriptions
    @store.store_env_data(
      root_thread_id: @root_id, key: "task",
      short_description: "The task", value: "data", stored_by: "solver"
    )
    @store.store_env_data(
      root_thread_id: @root_id, key: "findings",
      short_description: "Observed patterns", value: "data", stored_by: "observer"
    )

    cap = PromptObjects::Universal::ListEnvData.new
    result = cap.receive({}, context: @context)

    parsed = JSON.parse(result, symbolize_names: true)
    assert_equal 2, parsed.size
    assert_equal "task", parsed[1][:key] # sorted by key ASC
    assert_equal "findings", parsed[0][:key]
  end

  def test_list_env_data_empty
    cap = PromptObjects::Universal::ListEnvData.new
    result = cap.receive({}, context: @context)

    assert_match(/no environment data/i, result)
  end

  # --- update_env_data ---

  def test_update_env_data_updates_existing
    @store.store_env_data(
      root_thread_id: @root_id, key: "count",
      short_description: "A count", value: 1, stored_by: "counter"
    )

    cap = PromptObjects::Universal::UpdateEnvData.new
    result = cap.receive(
      { key: "count", value: 2 },
      context: @context
    )

    assert_equal "Updated 'count' in environment data.", result

    entry = @store.get_env_data(root_thread_id: @root_id, key: "count")
    assert_equal 2, entry[:value]
  end

  def test_update_env_data_not_found
    cap = PromptObjects::Universal::UpdateEnvData.new
    result = cap.receive(
      { key: "nonexistent", value: "something" },
      context: @context
    )

    assert_match(/not found.*store_env_data/i, result)
  end

  # --- delete_env_data ---

  def test_delete_env_data_deletes_existing
    @store.store_env_data(
      root_thread_id: @root_id, key: "temp",
      short_description: "Temp data", value: "data", stored_by: "test"
    )

    cap = PromptObjects::Universal::DeleteEnvData.new
    result = cap.receive({ key: "temp" }, context: @context)

    assert_equal "Deleted 'temp' from environment data.", result

    entry = @store.get_env_data(root_thread_id: @root_id, key: "temp")
    assert_nil entry
  end

  def test_delete_env_data_not_found
    cap = PromptObjects::Universal::DeleteEnvData.new
    result = cap.receive({ key: "nonexistent" }, context: @context)

    assert_match(/not found/, result)
  end

  # --- Error handling ---

  def test_error_when_session_store_unavailable
    no_store_env = Struct.new(:session_store, :registry).new(nil, @mock_registry)
    ctx = PromptObjects::Context.new(env: no_store_env, bus: @mock_bus)
    ctx.calling_po = "solver"

    cap = PromptObjects::Universal::StoreEnvData.new
    result = cap.receive(
      { key: "task", short_description: "desc", value: "data" },
      context: ctx
    )

    assert_match(/could not resolve thread scope/i, result)
  end

  def test_error_when_no_calling_po_session
    # Registry returns nil for unknown PO
    ctx = PromptObjects::Context.new(env: @mock_env, bus: @mock_bus)
    ctx.calling_po = "unknown_po"

    cap = PromptObjects::Universal::GetEnvData.new
    result = cap.receive({ key: "task" }, context: ctx)

    assert_match(/could not resolve thread scope/i, result)
  end
end
