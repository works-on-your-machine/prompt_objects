# frozen_string_literal: true

require_relative "../test_helper"

# Tests for the centralized PO serialization methods:
#   - to_state_hash: Full state for WebSocket real-time updates
#   - to_summary_hash: Compact summary for list endpoints
#   - to_inspect_hash: Detailed inspection for detail endpoints
#   - serialize_session: Session metadata serialization
#
# These methods are the single source of truth for all PO serialization.
# All consumers (WebSocket handler, REST API, MCP tools) delegate to them.
class POSerializationTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "serial_test"))
    create_test_po_file(@env_dir, name: "solver", description: "Solves problems", capabilities: ["read_file"])
    @runtime = create_test_runtime(env_path: @env_dir)
    @po = @runtime.load_prompt_object(File.join(@env_dir, "objects", "solver.md"))
  end

  # --- to_state_hash ---

  def test_to_state_hash_includes_all_required_fields
    result = @po.to_state_hash

    assert_equal "idle", result[:status]
    assert_equal "Solves problems", result[:description]
    assert_kind_of Array, result[:capabilities]
    assert_kind_of Array, result[:universal_capabilities]
    assert_kind_of Array, result[:sessions]
    assert result.key?(:prompt)
    assert result.key?(:config)
    assert result.key?(:current_session)
  end

  def test_to_state_hash_without_registry_returns_basic_capability_hashes
    result = @po.to_state_hash

    # Without registry, capabilities are hashes with name and description (name used as description)
    assert_kind_of Array, result[:capabilities]
    result[:capabilities].each do |cap|
      assert_kind_of Hash, cap
      assert cap.key?(:name)
      assert cap.key?(:description)
    end
  end

  def test_to_state_hash_with_registry_returns_rich_capabilities
    result = @po.to_state_hash(registry: @runtime.registry)

    # With registry, capabilities are hashes with name, description, parameters
    assert_kind_of Array, result[:capabilities]
    assert result[:capabilities].length > 0

    cap = result[:capabilities].first
    assert_kind_of Hash, cap
    assert cap.key?(:name)
    assert cap.key?(:description)
    assert cap.key?(:parameters)
    assert_equal "read_file", cap[:name]
  end

  def test_to_state_hash_with_registry_includes_universal_capabilities
    result = @po.to_state_hash(registry: @runtime.registry)

    assert result[:universal_capabilities].length > 0

    universal_names = result[:universal_capabilities].map { |c| c[:name] }
    assert_includes universal_names, "ask_human"
    assert_includes universal_names, "think"

    # Each universal capability should also be a rich hash
    result[:universal_capabilities].each do |cap|
      assert_kind_of Hash, cap
      assert cap.key?(:name)
      assert cap.key?(:description)
    end
  end

  def test_to_state_hash_reflects_status_changes
    @po.state = :thinking
    result = @po.to_state_hash
    assert_equal "thinking", result[:status]

    @po.state = :calling_tool
    result = @po.to_state_hash
    assert_equal "calling_tool", result[:status]

    @po.state = :idle
    result = @po.to_state_hash
    assert_equal "idle", result[:status]
  end

  # --- to_summary_hash ---

  def test_to_summary_hash_includes_required_fields
    result = @po.to_summary_hash

    assert_equal "solver", result[:name]
    assert_equal "Solves problems", result[:description]
    assert_equal "idle", result[:status]
    assert_kind_of Array, result[:capabilities]
    assert result.key?(:session_count)
  end

  def test_to_summary_hash_is_compact
    result = @po.to_summary_hash

    # Summary should NOT include heavy fields
    refute result.key?(:prompt)
    refute result.key?(:current_session)
    refute result.key?(:universal_capabilities)
    refute result.key?(:config)
  end

  def test_to_summary_hash_with_registry_returns_rich_capabilities
    result = @po.to_summary_hash(registry: @runtime.registry)

    cap = result[:capabilities].first
    assert_kind_of Hash, cap
    assert_equal "read_file", cap[:name]
    assert cap[:description]
  end

  # --- to_inspect_hash ---

  def test_to_inspect_hash_includes_all_detail_fields
    result = @po.to_inspect_hash

    assert_equal "solver", result[:name]
    assert_equal "Solves problems", result[:description]
    assert_equal "idle", result[:status]
    assert_kind_of Array, result[:capabilities]
    assert_kind_of Array, result[:universal_capabilities]
    assert result.key?(:prompt)
    assert result.key?(:config)
    assert result.key?(:session_id)
    assert result.key?(:sessions)
    assert result.key?(:history_length)
  end

  def test_to_inspect_hash_with_registry_returns_rich_capabilities
    result = @po.to_inspect_hash(registry: @runtime.registry)

    cap = result[:capabilities].first
    assert_kind_of Hash, cap
    assert_equal "read_file", cap[:name]

    # Universal should also be enriched
    universal_names = result[:universal_capabilities].map { |c| c[:name] }
    assert_includes universal_names, "ask_human"
  end

  # --- serialize_session ---

  def test_serialize_session_includes_all_fields
    session = {
      id: "abc123",
      name: "Test Thread",
      message_count: 5,
      updated_at: Time.new(2025, 1, 15, 12, 0, 0),
      parent_session_id: "parent123",
      parent_po: "coordinator",
      thread_type: "delegation"
    }

    result = PromptObjects::PromptObject.serialize_session(session)

    assert_equal "abc123", result[:id]
    assert_equal "Test Thread", result[:name]
    assert_equal 5, result[:message_count]
    assert result[:updated_at].start_with?("2025-01-15T12:00:00")
    assert_equal "parent123", result[:parent_session_id]
    assert_equal "coordinator", result[:parent_po]
    assert_equal "delegation", result[:thread_type]
  end

  def test_serialize_session_defaults_thread_type_to_root
    session = { id: "abc", name: nil, message_count: 0, updated_at: nil }

    result = PromptObjects::PromptObject.serialize_session(session)

    assert_equal "root", result[:thread_type]
  end

  def test_serialize_session_handles_nil_updated_at
    session = { id: "abc", name: nil, message_count: 0, updated_at: nil }

    result = PromptObjects::PromptObject.serialize_session(session)

    assert_nil result[:updated_at]
  end

  # --- Consistency: all serializers return rich capabilities with registry ---

  def test_all_serializers_agree_on_capability_format_with_registry
    state = @po.to_state_hash(registry: @runtime.registry)
    summary = @po.to_summary_hash(registry: @runtime.registry)
    inspect_h = @po.to_inspect_hash(registry: @runtime.registry)

    # All should return the same rich capability objects
    [state, summary, inspect_h].each do |result|
      cap = result[:capabilities].first
      assert_kind_of Hash, cap, "Expected rich capability hash, got #{cap.class}"
      assert_equal "read_file", cap[:name]
      assert cap[:description], "Capability should have a description"
    end
  end

  def test_all_serializers_agree_on_capability_format_without_registry
    state = @po.to_state_hash
    summary = @po.to_summary_hash
    inspect_h = @po.to_inspect_hash

    # Without registry, all should return basic hashes with name as description fallback
    [state, summary, inspect_h].each do |result|
      cap = result[:capabilities].first
      assert_kind_of Hash, cap, "Expected capability hash, got #{cap.class}"
      assert_equal "read_file", cap[:name]
    end
  end
end
