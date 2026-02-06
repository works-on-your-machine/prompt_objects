# frozen_string_literal: true

require_relative "../test_helper"

class MessageBusTest < PromptObjectsTest
  def setup
    super
    @bus = PromptObjects::MessageBus.new
  end

  def test_publish_stores_full_message
    @bus.publish(from: "human", to: "solver", message: "Hello world")

    entry = @bus.log.last
    assert_equal "Hello world", entry[:message]
  end

  def test_publish_stores_summary
    @bus.publish(from: "human", to: "solver", message: "Hello world")

    entry = @bus.log.last
    assert_equal "Hello world", entry[:summary]
  end

  def test_summary_truncates_long_messages
    long_message = "x" * 300
    @bus.publish(from: "human", to: "solver", message: long_message)

    entry = @bus.log.last
    # Full message preserved
    assert_equal 300, entry[:message].length
    # Summary truncated to 200 + "..."
    assert_equal 203, entry[:summary].length
    assert entry[:summary].end_with?("...")
  end

  def test_full_message_preserved_for_hash
    msg = { tool: "read_file", args: { path: "/some/long/path" }, result: "a" * 300 }
    @bus.publish(from: "solver", to: "read_file", message: msg)

    entry = @bus.log.last
    # Full hash preserved
    assert_equal msg, entry[:message]
    # Summary is JSON, truncated
    assert entry[:summary].is_a?(String)
  end

  def test_summary_collapses_whitespace
    msg = "line one\n  line two\n\n  line three"
    @bus.publish(from: "human", to: "solver", message: msg)

    entry = @bus.log.last
    # Full message keeps whitespace
    assert_includes entry[:message], "\n"
    # Summary collapses it
    assert_equal "line one line two line three", entry[:summary]
  end

  def test_format_log_uses_summary
    long_message = "x" * 300
    @bus.publish(from: "human", to: "solver", message: long_message)

    log_output = @bus.format_log
    # format_log should use the truncated summary, not the full message
    refute_includes log_output, "x" * 300
    assert_includes log_output, "x" * 200
  end

  def test_subscribers_receive_both_message_and_summary
    received = nil
    @bus.subscribe { |entry| received = entry }

    @bus.publish(from: "a", to: "b", message: "test message")

    assert received
    assert_equal "test message", received[:message]
    assert_equal "test message", received[:summary]
  end

  def test_entry_has_all_fields
    @bus.publish(from: "human", to: "solver", message: "hi")

    entry = @bus.log.last
    assert entry[:timestamp].is_a?(Time)
    assert_equal "human", entry[:from]
    assert_equal "solver", entry[:to]
    assert_equal "hi", entry[:message]
    assert_equal "hi", entry[:summary]
  end

  def test_recent_returns_entries_with_summary
    5.times { |i| @bus.publish(from: "a", to: "b", message: "msg #{i}") }

    entries = @bus.recent(3)
    assert_equal 3, entries.length
    entries.each do |entry|
      assert entry.key?(:summary), "Entry should have :summary key"
      assert entry.key?(:message), "Entry should have :message key"
    end
  end

  def test_unsubscribe
    count = 0
    handler = proc { |_| count += 1 }

    @bus.subscribe(&handler)
    @bus.publish(from: "a", to: "b", message: "first")
    assert_equal 1, count

    @bus.unsubscribe(handler)
    @bus.publish(from: "a", to: "b", message: "second")
    assert_equal 1, count
  end

  def test_clear
    @bus.publish(from: "a", to: "b", message: "msg")
    assert_equal 1, @bus.log.length

    @bus.clear
    assert_equal 0, @bus.log.length
  end
end
