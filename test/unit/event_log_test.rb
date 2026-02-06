# frozen_string_literal: true

require_relative "../test_helper"

class EventLogTest < PromptObjectsTest
  def setup
    super
    @store = create_memory_store
  end

  def teardown
    @store.close
    super
  end

  # --- Store: events table ---

  def test_add_event
    entry = {
      timestamp: Time.now,
      from: "human",
      to: "solver",
      message: "Hello",
      summary: "Hello"
    }

    id = @store.add_event(entry)
    assert id > 0
  end

  def test_add_event_with_session_id
    entry = {
      timestamp: Time.now,
      from: "solver",
      to: "read_file",
      message: { path: "/foo.txt" },
      summary: '{"path":"/foo.txt"}'
    }

    id = @store.add_event(entry, session_id: "sess-123")
    events = @store.get_events(session_id: "sess-123")

    assert_equal 1, events.length
    assert_equal "solver", events[0][:from]
    assert_equal "read_file", events[0][:to]
  end

  def test_get_events_by_session
    2.times do |i|
      @store.add_event(
        { timestamp: Time.now, from: "a", to: "b", message: "msg #{i}", summary: "msg #{i}" },
        session_id: "sess-A"
      )
    end
    @store.add_event(
      { timestamp: Time.now, from: "a", to: "b", message: "other", summary: "other" },
      session_id: "sess-B"
    )

    events_a = @store.get_events(session_id: "sess-A")
    events_b = @store.get_events(session_id: "sess-B")

    assert_equal 2, events_a.length
    assert_equal 1, events_b.length
  end

  def test_get_events_since
    t1 = Time.now - 60
    t2 = Time.now - 30
    t3 = Time.now

    @store.add_event({ timestamp: t1, from: "a", to: "b", message: "old", summary: "old" })
    @store.add_event({ timestamp: t2, from: "a", to: "b", message: "mid", summary: "mid" })
    @store.add_event({ timestamp: t3, from: "a", to: "b", message: "new", summary: "new" })

    events = @store.get_events_since(t2.iso8601)
    assert_equal 1, events.length
    assert_equal "new", events[0][:message]
  end

  def test_get_events_between
    t1 = Time.now - 60
    t2 = Time.now - 30
    t3 = Time.now

    @store.add_event({ timestamp: t1, from: "a", to: "b", message: "old", summary: "old" })
    @store.add_event({ timestamp: t2, from: "a", to: "b", message: "mid", summary: "mid" })
    @store.add_event({ timestamp: t3, from: "a", to: "b", message: "new", summary: "new" })

    events = @store.get_events_between((t1 - 1).iso8601, (t2 + 1).iso8601)
    assert_equal 2, events.length
  end

  def test_get_recent_events
    5.times { |i| @store.add_event({ timestamp: Time.now, from: "a", to: "b", message: "msg #{i}", summary: "msg #{i}" }) }

    events = @store.get_recent_events(3)
    assert_equal 3, events.length
    # Should be in chronological order (oldest first)
    assert_equal "msg 2", events[0][:message]
    assert_equal "msg 4", events[2][:message]
  end

  def test_search_events
    @store.add_event({ timestamp: Time.now, from: "solver", to: "grid_diff", message: "comparing grids", summary: "comparing grids" })
    @store.add_event({ timestamp: Time.now, from: "solver", to: "read_file", message: "reading task", summary: "reading task" })

    results = @store.search_events("grid")
    assert_equal 1, results.length
    assert_equal "grid_diff", results[0][:to]
  end

  def test_total_events
    assert_equal 0, @store.total_events

    3.times { @store.add_event({ timestamp: Time.now, from: "a", to: "b", message: "m", summary: "m" }) }
    assert_equal 3, @store.total_events
  end

  def test_event_stores_hash_message_as_json
    msg = { tool: "read_file", path: "/foo.txt" }
    @store.add_event({ timestamp: Time.now, from: "a", to: "b", message: msg, summary: "read_file" })

    events = @store.get_recent_events(1)
    # Stored as JSON string
    assert_includes events[0][:message], "read_file"
    assert_includes events[0][:message], "/foo.txt"
  end

  # --- MessageBus + Store integration ---

  def test_bus_persists_events_when_store_provided
    bus = PromptObjects::MessageBus.new(session_store: @store)
    bus.publish(from: "human", to: "solver", message: "test message")

    events = @store.get_recent_events(10)
    assert_equal 1, events.length
    assert_equal "human", events[0][:from]
    assert_equal "solver", events[0][:to]
    assert_equal "test message", events[0][:message]
    assert_equal "test message", events[0][:summary]
  end

  def test_bus_persists_with_session_id
    bus = PromptObjects::MessageBus.new(session_store: @store)
    bus.publish(from: "a", to: "b", message: "hello", session_id: "my-session")

    events = @store.get_events(session_id: "my-session")
    assert_equal 1, events.length
  end

  def test_bus_without_store_works_fine
    bus = PromptObjects::MessageBus.new
    entry = bus.publish(from: "a", to: "b", message: "test")

    assert_equal "test", entry[:message]
    assert_equal 1, bus.log.length
  end

  def test_bus_persistence_failure_does_not_break_bus
    # Use a store then close it to force failures
    bus = PromptObjects::MessageBus.new(session_store: @store)
    @store.close

    # Should not raise — warn and continue
    entry = bus.publish(from: "a", to: "b", message: "after close")
    assert_equal "after close", entry[:message]
    assert_equal 1, bus.log.length
  end

  # --- Runtime integration ---

  def test_runtime_wires_bus_to_store
    env_dir = track_temp_dir(create_temp_env(name: "bus_test"))
    runtime = PromptObjects::Runtime.new(env_path: env_dir, llm: MockLLM.new)

    # Publish via the runtime's bus
    runtime.bus.publish(from: "human", to: "test", message: "integration test")

    # Should be persisted in the store
    events = runtime.session_store.get_recent_events(10)
    assert_equal 1, events.length
    assert_equal "integration test", events[0][:message]
  end

  def test_legacy_runtime_bus_has_no_store
    runtime = PromptObjects::Runtime.new(objects_dir: "/tmp/nonexistent", llm: MockLLM.new)

    # Should work fine without persistence
    entry = runtime.bus.publish(from: "a", to: "b", message: "legacy")
    assert_equal "legacy", entry[:message]
  end
end
