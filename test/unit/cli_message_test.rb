# frozen_string_literal: true

require_relative "../test_helper"
require "json"
require "open3"

class CliMessageTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "cli_test"))
    create_test_po_file(@env_dir, name: "solver", capabilities: ["read_file"])
  end

  def test_message_standalone_returns_response
    out, err, status = run_cli("message", @env_dir, "solver", "Hello")

    assert status.success?, "CLI should succeed, stderr: #{err}"
    refute out.strip.empty?, "Should return a non-empty response"
  end

  def test_message_standalone_json_output
    out, err, status = run_cli("message", @env_dir, "solver", "Hello", "--json")

    assert status.success?, "CLI should succeed, stderr: #{err}"
    data = JSON.parse(out)
    assert data["response"], "JSON should have response key"
    assert data["po_name"], "JSON should have po_name key"
    assert data["session_id"], "JSON should have session_id key"
  end

  def test_message_standalone_with_events
    out, err, status = run_cli("message", @env_dir, "solver", "Hello", "--events")

    assert status.success?, "CLI should succeed"
    # Events are printed to stderr
    assert err.include?("Events"), "Should show events header in stderr"
    assert err.include?("human -> solver"), "Should show human->solver event"
    assert err.include?("solver -> human"), "Should show solver->human event"
  end

  def test_message_missing_args
    out, _err, status = run_cli("message")

    refute status.success?
    assert out.include?("Error") || out.include?("required")
  end

  def test_message_unknown_environment
    _out, err, status = run_cli("message", "nonexistent_env_xyz", "solver", "Hello")

    refute status.success?
    assert err.include?("not found"), "Should report env not found, got: #{err}"
  end

  def test_message_unknown_po
    _out, err, status = run_cli("message", @env_dir, "nonexistent_po", "Hello")

    refute status.success?
    assert err.include?("not found"), "Should report PO not found, got: #{err}"
  end

  def test_events_standalone
    # First send a message to create some events
    run_cli("message", @env_dir, "solver", "Generate events")

    # Then query events
    out, _err, status = run_cli("events", @env_dir)

    assert status.success?, "events command should succeed"
    assert out.include?("solver"), "Should show events involving solver"
  end

  def test_events_json_output
    # Send a message first
    run_cli("message", @env_dir, "solver", "Generate events")

    out, _err, status = run_cli("events", @env_dir, "--json")

    assert status.success?
    data = JSON.parse(out)
    assert data.is_a?(Array), "JSON events should be an array"
    assert data.length > 0, "Should have events"
  end

  private

  def run_cli(*args)
    exe = File.expand_path("../../exe/prompt_objects", __dir__)
    env = { "BUNDLE_GEMFILE" => File.expand_path("../../Gemfile", __dir__) }
    Open3.capture3(env, "bundle", "exec", "ruby", exe, *args)
  end
end
