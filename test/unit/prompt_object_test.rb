# frozen_string_literal: true

require_relative "../test_helper"

class PromptObjectTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "test_env"))
    @runtime = create_test_runtime(env_path: @env_dir)
  end

  # --- Loader Tests ---

  def test_loader_parses_frontmatter_and_body
    path = create_test_po_file(@env_dir, name: "test", description: "A test PO", capabilities: ["read_file"])

    data = PromptObjects::Loader.load(path)

    assert_equal "test", data[:config]["name"]
    assert_equal "A test PO", data[:config]["description"]
    assert_equal ["read_file"], data[:config]["capabilities"]
    assert_includes data[:body], "You are a test prompt object"
    assert_equal path, data[:path]
  end

  def test_loader_handles_empty_capabilities
    path = create_test_po_file(@env_dir, name: "empty", capabilities: [])

    data = PromptObjects::Loader.load(path)

    # YAML may parse empty array as nil or []
    caps = data[:config]["capabilities"] || []
    assert_equal [], caps
  end

  def test_loader_raises_for_missing_file
    assert_raises(PromptObjects::Error) do
      PromptObjects::Loader.load("/nonexistent/path.md")
    end
  end

  def test_loader_load_all_finds_all_md_files
    create_test_po_file(@env_dir, name: "one")
    create_test_po_file(@env_dir, name: "two")
    create_test_po_file(@env_dir, name: "three")

    objects_dir = File.join(@env_dir, "objects")
    data = PromptObjects::Loader.load_all(objects_dir)

    assert_equal 3, data.length
    names = data.map { |d| d[:config]["name"] }
    assert_includes names, "one"
    assert_includes names, "two"
    assert_includes names, "three"
  end

  # --- PromptObject Initialization ---

  def test_prompt_object_initializes_with_config_and_body
    path = create_test_po_file(@env_dir, name: "assistant", description: "Helpful assistant")

    po = @runtime.load_prompt_object(path)

    assert_equal "assistant", po.name
    assert_equal "Helpful assistant", po.description
    assert_equal path, po.path
  end

  def test_prompt_object_defaults_name_to_unnamed
    # Create a PO file without a name
    content = <<~MD
      ---
      description: No name PO
      ---

      You have no name.
    MD

    path = File.join(@env_dir, "objects", "noname.md")
    File.write(path, content)

    po = @runtime.load_prompt_object(path)

    assert_equal "unnamed", po.name
  end

  def test_prompt_object_defaults_description
    content = <<~MD
      ---
      name: minimal
      ---

      Minimal PO.
    MD

    path = File.join(@env_dir, "objects", "minimal.md")
    File.write(path, content)

    po = @runtime.load_prompt_object(path)

    assert_equal "A prompt object", po.description
  end

  def test_prompt_object_has_message_parameter_schema
    path = create_test_po_file(@env_dir, name: "test")
    po = @runtime.load_prompt_object(path)

    params = po.parameters

    assert_equal "object", params[:type]
    assert params[:properties].key?(:message)
    assert_equal "string", params[:properties][:message][:type]
    assert_equal ["message"], params[:required]
  end

  def test_prompt_object_generates_descriptor
    path = create_test_po_file(@env_dir, name: "helper", description: "A helper")
    po = @runtime.load_prompt_object(path)

    descriptor = po.descriptor

    assert_equal "function", descriptor[:type]
    assert_equal "helper", descriptor[:function][:name]
    assert_equal "A helper", descriptor[:function][:description]
    assert descriptor[:function][:parameters]
  end

  # --- Message Handling ---

  def test_receive_processes_simple_message
    path = create_test_po_file(@env_dir, name: "echo")
    po = @runtime.load_prompt_object(path)

    response = po.receive("Hello!", context: @runtime.context)

    assert_equal "Mock response from LLM", response
  end

  def test_receive_adds_message_to_history
    path = create_test_po_file(@env_dir, name: "history_test")
    po = @runtime.load_prompt_object(path)

    po.receive("First message", context: @runtime.context)

    assert_equal 2, po.history.length  # user + assistant
    assert_equal :user, po.history[0][:role]
    assert_equal "First message", po.history[0][:content]
    assert_equal :assistant, po.history[1][:role]
  end

  def test_receive_tracks_sender_as_human_by_default
    path = create_test_po_file(@env_dir, name: "sender_test")
    po = @runtime.load_prompt_object(path)

    po.receive("Hello", context: @runtime.context)

    assert_equal "human", po.history[0][:from]
  end

  def test_receive_normalizes_hash_message
    path = create_test_po_file(@env_dir, name: "hash_test")
    po = @runtime.load_prompt_object(path)

    po.receive({ message: "From hash" }, context: @runtime.context)

    assert_equal "From hash", po.history[0][:content]
  end

  def test_receive_handles_tool_calls
    path = create_test_po_file(@env_dir, name: "tool_test", capabilities: ["read_file"])
    po = @runtime.load_prompt_object(path)

    # Queue a response with a tool call, then a final response
    mock_llm = @runtime.llm
    mock_llm.queue_response(
      tool_calls: [
        PromptObjects::LLM::ToolCall.new(
          id: "call_123",
          name: "read_file",
          arguments: { "path" => "/tmp/test.txt" }
        )
      ]
    )
    mock_llm.queue_response(content: "I read the file!")

    response = po.receive("Read the file", context: @runtime.context)

    assert_equal "I read the file!", response
    # History should have: user, assistant (tool call), tool, assistant (final)
    assert_equal 4, po.history.length
  end

  # --- Session Management ---

  def test_new_session_creates_fresh_session
    path = create_test_po_file(@env_dir, name: "session_test")
    po = @runtime.load_prompt_object(path)

    # Add some history
    po.receive("Message 1", context: @runtime.context)
    assert po.history.length > 0

    # Create new session
    old_session = po.session_id
    new_id = po.new_session(name: "Fresh Start")

    assert new_id
    refute_equal old_session, new_id
    assert_empty po.history
  end

  def test_switch_session_loads_existing_history
    path = create_test_po_file(@env_dir, name: "switch_test")
    po = @runtime.load_prompt_object(path)

    # Create first session with messages
    first_session = po.session_id
    po.receive("Session 1 message", context: @runtime.context)

    # Create new session
    second_session = po.new_session
    po.receive("Session 2 message", context: @runtime.context)

    # Switch back to first session
    result = po.switch_session(first_session)

    assert result
    assert_equal first_session, po.session_id
    assert_equal "Session 1 message", po.history.first[:content]
  end

  def test_switch_session_returns_false_for_wrong_po
    path1 = create_test_po_file(@env_dir, name: "po1")
    path2 = create_test_po_file(@env_dir, name: "po2")

    po1 = @runtime.load_prompt_object(path1)
    po2 = @runtime.load_prompt_object(path2)

    # Try to switch po2 to po1's session
    result = po2.switch_session(po1.session_id)

    refute result
  end

  def test_clear_history_removes_messages
    path = create_test_po_file(@env_dir, name: "clear_test")
    po = @runtime.load_prompt_object(path)

    po.receive("Hello", context: @runtime.context)
    assert po.history.length > 0

    po.clear_history

    assert_empty po.history
  end

  def test_list_sessions_returns_all_sessions
    path = create_test_po_file(@env_dir, name: "list_test")
    po = @runtime.load_prompt_object(path)

    # PO starts with 1 session on load, then we create 2 more
    po.new_session(name: "Session 2")
    po.new_session(name: "Session 3")

    sessions = po.list_sessions

    assert_equal 3, sessions.length
  end

  # --- File Persistence ---

  def test_save_persists_config_changes
    path = create_test_po_file(@env_dir, name: "save_test", capabilities: ["existing"])
    po = @runtime.load_prompt_object(path)

    # Modify config
    po.config["capabilities"] << "read_file"
    po.config["capabilities"] << "write_file"

    result = po.save

    assert result

    # Reload and verify
    reloaded = PromptObjects::Loader.load(path)
    assert_equal ["existing", "read_file", "write_file"], reloaded[:config]["capabilities"]
  end

  def test_save_returns_false_without_path
    # Create PO without path
    po = PromptObjects::PromptObject.new(
      config: { "name" => "no_path" },
      body: "Test body",
      env: @runtime,
      llm: @runtime.llm,
      path: nil
    )

    result = po.save

    refute result
  end

  def test_save_preserves_body
    content = <<~MD
      ---
      name: body_test
      description: Test body preservation
      capabilities: []
      ---

      # Custom Body

      This is a custom body with **markdown**.

      - Item 1
      - Item 2
    MD

    path = File.join(@env_dir, "objects", "body_test.md")
    File.write(path, content)
    po = @runtime.load_prompt_object(path)

    # Modify config and save
    po.config["capabilities"] << "new_cap"
    po.save

    # Reload and verify body is preserved
    reloaded = PromptObjects::Loader.load(path)
    assert_includes reloaded[:body], "# Custom Body"
    assert_includes reloaded[:body], "**markdown**"
  end

  # --- Thread/Delegation Support ---

  def test_create_delegation_thread
    path = create_test_po_file(@env_dir, name: "delegate_test")
    po = @runtime.load_prompt_object(path)

    thread_id = po.create_delegation_thread(
      parent_po: "caller_po",
      parent_session_id: "parent-session-123"
    )

    assert thread_id
    refute_equal po.session_id, thread_id

    # Verify thread metadata in session store
    session = @runtime.session_store.get_session(thread_id)
    assert_equal "delegation", session[:thread_type]
    assert_equal "caller_po", session[:parent_po]
  end

  def test_receive_in_thread_isolates_history
    path = create_test_po_file(@env_dir, name: "thread_test")
    po = @runtime.load_prompt_object(path)

    # Add message to main session
    po.receive("Main session message", context: @runtime.context)
    main_history_size = po.history.length
    main_session = po.session_id

    # Create and use delegation thread
    thread_id = po.create_delegation_thread(
      parent_po: "caller",
      parent_session_id: "parent-123"
    )

    response = po.receive_in_thread("Thread message", context: @runtime.context, thread_id: thread_id)

    # Verify we're back in main session with original history
    assert_equal main_session, po.session_id
    assert_equal main_history_size, po.history.length
    assert_equal "Mock response from LLM", response
  end

  def test_new_thread_creates_root_thread
    path = create_test_po_file(@env_dir, name: "root_thread_test")
    po = @runtime.load_prompt_object(path)

    old_session = po.session_id
    new_id = po.new_thread(name: "New Root Thread")

    assert new_id
    refute_equal old_session, new_id
    assert_empty po.history

    # Verify thread type
    session = @runtime.session_store.get_session(new_id)
    assert_equal "root", session[:thread_type]
  end

  # --- State Management ---

  def test_initial_state_is_idle
    path = create_test_po_file(@env_dir, name: "state_test")
    po = @runtime.load_prompt_object(path)

    assert_equal :idle, po.state
  end

  # --- Integration with Runtime ---

  def test_runtime_registers_loaded_po
    path = create_test_po_file(@env_dir, name: "registered")

    po = @runtime.load_prompt_object(path)

    assert_equal po, @runtime.get("registered")
    assert_includes @runtime.loaded_objects, "registered"
  end

  def test_runtime_load_by_name
    create_test_po_file(@env_dir, name: "by_name")

    po = @runtime.load_by_name("by_name")

    assert_equal "by_name", po.name
  end
end
