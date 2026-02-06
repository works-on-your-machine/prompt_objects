# frozen_string_literal: true

require_relative "../../test_helper"
require "json"

class RestApiTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "api_test"))
    create_test_po_file(@env_dir, name: "solver", capabilities: ["read_file"])

    @llm = MockLLM.new
    @llm.queue_response(content: "I solved it!")
    @runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: @llm)
    @runtime.load_prompt_object(File.join(@env_dir, "objects", "solver.md"))

    require "prompt_objects/server/api/routes"
    @routes = PromptObjects::Server::API::Routes.new(@runtime)
  end

  # --- Server discovery ---

  def test_write_and_read_server_file
    require "prompt_objects/server"

    path = PromptObjects::Server.write_server_file(@env_dir, host: "localhost", port: 3000)
    assert File.exist?(path)

    data = PromptObjects::Server.read_server_file(@env_dir)
    assert data
    assert_equal Process.pid, data[:pid]
    assert_equal "localhost", data[:host]
    assert_equal 3000, data[:port]
  ensure
    File.delete(path) if path && File.exist?(path)
  end

  def test_read_server_file_returns_nil_when_missing
    require "prompt_objects/server"

    data = PromptObjects::Server.read_server_file(@env_dir)
    assert_nil data
  end

  def test_read_server_file_cleans_stale_file
    require "prompt_objects/server"

    # Write a server file with a dead PID
    server_file = File.join(@env_dir, ".server")
    File.write(server_file, JSON.generate({ pid: 999999999, host: "localhost", port: 3000 }))

    data = PromptObjects::Server.read_server_file(@env_dir)
    assert_nil data
    refute File.exist?(server_file), "Stale server file should be cleaned up"
  end

  def test_remove_server_file
    require "prompt_objects/server"

    path = PromptObjects::Server.write_server_file(@env_dir, host: "localhost", port: 3000)
    assert File.exist?(path)

    PromptObjects::Server.remove_server_file(path)
    refute File.exist?(path)
  end

  # --- POST /api/prompt_objects/:name/message ---

  def test_send_message_endpoint
    env = mock_rack_env("POST", "/api/prompt_objects/solver/message", body: { message: "Hello solver" }.to_json)
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert_equal "I solved it!", data["response"]
    assert_equal "solver", data["po_name"]
    assert data["session_id"]
  end

  def test_send_message_missing_message
    env = mock_rack_env("POST", "/api/prompt_objects/solver/message", body: { message: "" }.to_json)
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert_equal "Message is required", data["error"]
  end

  def test_send_message_unknown_po
    env = mock_rack_env("POST", "/api/prompt_objects/nonexistent/message", body: { message: "hi" }.to_json)
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert_equal "Prompt object not found", data["error"]
  end

  def test_send_message_invalid_json
    env = mock_rack_env("POST", "/api/prompt_objects/solver/message", body: "not json")
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert_equal "Invalid JSON body", data["error"]
  end

  def test_send_message_with_new_thread
    env = mock_rack_env("POST", "/api/prompt_objects/solver/message", body: { message: "Hi", new_thread: true }.to_json)
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert data["session_id"]
    assert data["response"]
  end

  # --- GET /api/events ---

  def test_get_recent_events
    # Publish some events via the bus
    @runtime.bus.publish(from: "human", to: "solver", message: "test event")

    env = mock_rack_env("GET", "/api/events")
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert data["events"]
    assert data["events"].length >= 1
    assert_equal "human", data["events"].first["from"]
  end

  # --- GET /api/events/session/:id ---

  def test_get_session_events
    session_id = "test-session-123"
    @runtime.bus.publish(from: "a", to: "b", message: "session event", session_id: session_id)

    env = mock_rack_env("GET", "/api/events/session/#{session_id}")
    status, _headers, body = @routes.call(env)

    assert_equal 200, status
    data = JSON.parse(body.first)
    assert_equal 1, data["events"].length
    assert_equal "session event", data["events"].first["message"]
  end

  private

  # Create a minimal Rack env hash for testing routes
  def mock_rack_env(method, path, body: nil)
    env = {
      "REQUEST_METHOD" => method,
      "PATH_INFO" => path,
      "QUERY_STRING" => "",
      "rack.input" => StringIO.new(body || "")
    }
    env
  end
end
