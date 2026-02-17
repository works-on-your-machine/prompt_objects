# frozen_string_literal: true

require_relative "../test_helper"

class MessageProvenanceTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "provenance_test"))
    @runtime = create_test_runtime(env_path: @env_dir)
  end

  # --- Layer 1: System Prompt Tests ---

  def test_system_prompt_includes_po_identity
    path = create_test_po_file(@env_dir, name: "observer", description: "Observes patterns")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, 'You are a prompt object named "observer" running in a PromptObjects environment'
  end

  def test_system_prompt_includes_what_is_a_prompt_object
    path = create_test_po_file(@env_dir, name: "test_po")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "### What is a Prompt Object?"
    assert_includes prompt, "autonomous entity defined by a markdown file"
  end

  def test_system_prompt_includes_how_you_get_called
    path = create_test_po_file(@env_dir, name: "test_po")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "### How you get called"
    assert_includes prompt, "**A human**"
    assert_includes prompt, "**Another prompt object**"
  end

  def test_system_prompt_includes_env_data_hint
    path = create_test_po_file(@env_dir, name: "test_po")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "list_env_data"
  end

  def test_system_prompt_includes_declared_capabilities
    path = create_test_po_file(@env_dir, name: "reader", capabilities: ["read_file", "list_files"])
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "Declared capabilities: read_file, list_files"
  end

  def test_system_prompt_shows_none_for_empty_capabilities
    path = create_test_po_file(@env_dir, name: "bare")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "Declared capabilities: (none)"
  end

  def test_system_prompt_includes_universal_capabilities
    path = create_test_po_file(@env_dir, name: "test_po")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "Universal capabilities (always available): "
    assert_includes prompt, "ask_human"
    assert_includes prompt, "think"
    assert_includes prompt, "store_env_data"
  end

  def test_system_prompt_body_comes_before_context
    path = create_test_po_file(@env_dir, name: "order_test")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    body_pos = prompt.index("You are a test prompt object")
    context_pos = prompt.index("## System Context")

    assert body_pos, "Body should be present in prompt"
    assert context_pos, "System context should be present in prompt"
    assert body_pos < context_pos, "Body should come before system context"
  end

  def test_system_prompt_includes_self_modification_hint
    path = create_test_po_file(@env_dir, name: "test_po")
    po = @runtime.load_prompt_object(path)

    prompt = po.send(:build_system_prompt)

    assert_includes prompt, "create_primitive"
    assert_includes prompt, "create_capability"
    assert_includes prompt, "list_capabilities"
  end

  def test_system_prompt_sent_to_llm
    path = create_test_po_file(@env_dir, name: "llm_test")
    po = @runtime.load_prompt_object(path)

    po.receive("Hello", context: @runtime.context)

    system_prompt = @runtime.llm.calls.last[:system]
    assert_includes system_prompt, 'You are a prompt object named "llm_test"'
    assert_includes system_prompt, "### What is a Prompt Object?"
  end

  # --- Layer 2: Preamble Unit Tests ---

  def test_build_delegation_preamble_includes_caller_info
    caller_path = create_test_po_file(@env_dir, name: "solver", description: "Solves puzzles")
    target_path = create_test_po_file(@env_dir, name: "observer", description: "Observes patterns")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    # Create a delegation thread
    thread_id = target_po.create_delegation_thread(
      parent_po: "solver",
      parent_session_id: caller_po.session_id
    )

    ctx = @runtime.context
    ctx.calling_po = "solver"

    preamble = target_po.send(:build_delegation_preamble, target_po, thread_id, ctx)

    assert_includes preamble, "Called by: solver"
    assert_includes preamble, 'solver is: "Solves puzzles"'
    assert_includes preamble, "[Delegation Context]"
  end

  def test_build_delegation_preamble_returns_nil_without_calling_po
    path = create_test_po_file(@env_dir, name: "target")
    po = @runtime.load_prompt_object(path)

    ctx = @runtime.context
    ctx.calling_po = nil

    preamble = po.send(:build_delegation_preamble, po, "some-thread", ctx)

    assert_nil preamble
  end

  def test_build_delegation_preamble_returns_nil_for_primitive_caller
    target_path = create_test_po_file(@env_dir, name: "target")
    target_po = @runtime.load_prompt_object(target_path)

    ctx = @runtime.context
    ctx.calling_po = "read_file"  # A primitive, not a PO

    preamble = target_po.send(:build_delegation_preamble, target_po, "some-thread", ctx)

    assert_nil preamble
  end

  def test_build_delegation_chain_produces_correct_chain
    # Set up a chain: human → coordinator → solver → observer
    coord_path = create_test_po_file(@env_dir, name: "coordinator", description: "Coordinates")
    solver_path = create_test_po_file(@env_dir, name: "solver", description: "Solves")
    observer_path = create_test_po_file(@env_dir, name: "observer", description: "Observes")

    coord = @runtime.load_prompt_object(coord_path)
    solver = @runtime.load_prompt_object(solver_path)
    observer = @runtime.load_prompt_object(observer_path)

    # coordinator's root session
    coord_session = coord.session_id

    # solver delegation thread (child of coordinator)
    solver_thread = solver.create_delegation_thread(
      parent_po: "coordinator",
      parent_session_id: coord_session
    )

    # observer delegation thread (child of solver)
    observer_thread = observer.create_delegation_thread(
      parent_po: "solver",
      parent_session_id: solver_thread
    )

    chain = observer.send(:build_delegation_chain, observer_thread)

    assert_includes chain, "human"
    assert_includes chain, "coordinator"
    assert_includes chain, "solver"
    assert_includes chain, "you (observer)"
    # Verify ordering
    assert_match(/human.*coordinator.*solver.*you \(observer\)/, chain)
  end

  def test_build_delegation_chain_returns_nil_without_session_store
    # Create PO without session store (legacy mode)
    po = PromptObjects::PromptObject.new(
      config: { "name" => "no_store" },
      body: "Test body",
      env: @runtime,
      llm: @runtime.llm,
      path: nil
    )

    # Override session_store to return nil
    po.define_singleton_method(:session_store) { nil }

    chain = po.send(:build_delegation_chain, "some-thread")

    assert_nil chain
  end

  def test_env_data_available_returns_true_when_data_exists
    path = create_test_po_file(@env_dir, name: "data_test")
    po = @runtime.load_prompt_object(path)

    # Create a delegation thread
    thread_id = po.create_delegation_thread(
      parent_po: "caller",
      parent_session_id: po.session_id
    )

    # Store some env data scoped to the root thread
    root_thread = @runtime.session_store.resolve_root_thread(thread_id)
    @runtime.session_store.store_env_data(
      root_thread_id: root_thread,
      key: "test_key",
      short_description: "Test data",
      value: { hello: "world" },
      stored_by: "caller"
    )

    result = po.send(:env_data_available?, thread_id)

    assert result
  end

  def test_env_data_available_returns_false_when_no_data
    path = create_test_po_file(@env_dir, name: "empty_data_test")
    po = @runtime.load_prompt_object(path)

    thread_id = po.create_delegation_thread(
      parent_po: "caller",
      parent_session_id: po.session_id
    )

    result = po.send(:env_data_available?, thread_id)

    refute result
  end

  def test_preamble_includes_env_data_hint_when_data_exists
    caller_path = create_test_po_file(@env_dir, name: "caller_po", description: "Calls things")
    target_path = create_test_po_file(@env_dir, name: "target_po", description: "Gets called")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    thread_id = target_po.create_delegation_thread(
      parent_po: "caller_po",
      parent_session_id: caller_po.session_id
    )

    # Store env data
    root_thread = @runtime.session_store.resolve_root_thread(thread_id)
    @runtime.session_store.store_env_data(
      root_thread_id: root_thread,
      key: "grid_data",
      short_description: "ARC grid",
      value: [[1, 2], [3, 4]],
      stored_by: "caller_po"
    )

    ctx = @runtime.context
    ctx.calling_po = "caller_po"

    preamble = target_po.send(:build_delegation_preamble, target_po, thread_id, ctx)

    assert_includes preamble, "Shared environment data is available"
    assert_includes preamble, "list_env_data()"
  end

  def test_preamble_omits_env_data_hint_when_no_data
    caller_path = create_test_po_file(@env_dir, name: "caller2", description: "Calls things")
    target_path = create_test_po_file(@env_dir, name: "target2", description: "Gets called")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    thread_id = target_po.create_delegation_thread(
      parent_po: "caller2",
      parent_session_id: caller_po.session_id
    )

    ctx = @runtime.context
    ctx.calling_po = "caller2"

    preamble = target_po.send(:build_delegation_preamble, target_po, thread_id, ctx)

    refute_includes preamble, "Shared environment data is available"
  end

  # --- Layer 2: enrich_delegation_message Tests ---

  def test_enrich_delegation_message_with_hash_arguments
    caller_path = create_test_po_file(@env_dir, name: "enricher", description: "Enriches")
    target_path = create_test_po_file(@env_dir, name: "enriched", description: "Gets enriched")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    thread_id = target_po.create_delegation_thread(
      parent_po: "enricher",
      parent_session_id: caller_po.session_id
    )

    ctx = @runtime.context
    ctx.calling_po = "enricher"

    original_args = { "message" => "What patterns do you see?" }
    enriched = target_po.send(:enrich_delegation_message, target_po, original_args, thread_id, ctx)

    # Should be a new hash, not the original
    refute_same original_args, enriched
    # Original should be unchanged
    assert_equal "What patterns do you see?", original_args["message"]
    # Enriched should contain preamble + original message
    assert_includes enriched["message"], "[Delegation Context]"
    assert_includes enriched["message"], "What patterns do you see?"
  end

  def test_enrich_delegation_message_returns_original_without_preamble
    path = create_test_po_file(@env_dir, name: "no_preamble")
    po = @runtime.load_prompt_object(path)

    ctx = @runtime.context
    ctx.calling_po = nil  # No caller = no preamble

    original_args = { "message" => "Hello" }
    result = po.send(:enrich_delegation_message, po, original_args, nil, ctx)

    assert_same original_args, result
  end

  def test_enrich_delegation_message_does_not_mutate_original
    caller_path = create_test_po_file(@env_dir, name: "mutator", description: "Tests mutation")
    target_path = create_test_po_file(@env_dir, name: "target_mut", description: "Target")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    thread_id = target_po.create_delegation_thread(
      parent_po: "mutator",
      parent_session_id: caller_po.session_id
    )

    ctx = @runtime.context
    ctx.calling_po = "mutator"

    original_args = { "message" => "Original message" }
    original_message_copy = original_args["message"].dup

    target_po.send(:enrich_delegation_message, target_po, original_args, thread_id, ctx)

    assert_equal original_message_copy, original_args["message"]
  end

  # --- Integration Tests ---

  def test_delegated_message_starts_with_delegation_context
    caller_path = create_test_po_file(@env_dir, name: "int_caller", description: "Integration caller", capabilities: ["int_target"])
    target_path = create_test_po_file(@env_dir, name: "int_target", description: "Integration target")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    # Set up mock LLM for caller: first call returns a tool call to int_target, second is final
    mock_llm = @runtime.llm
    mock_llm.queue_response(
      tool_calls: [
        PromptObjects::LLM::ToolCall.new(
          id: "call_001",
          name: "int_target",
          arguments: { "message" => "Analyze this" }
        )
      ]
    )
    mock_llm.queue_response(content: "Target response")  # target PO's response
    mock_llm.queue_response(content: "Caller final response")  # caller's final response after tool result

    response = caller_po.receive("Do something", context: @runtime.context)

    # The target PO should have received a message with delegation context
    # Check the LLM calls - the second call should be the target PO's call with preamble
    target_call = mock_llm.calls[1]
    assert target_call, "Target PO should have been called"

    user_message = target_call[:messages].find { |m| m[:role] == :user }
    assert user_message, "Target should have a user message"
    assert_includes user_message[:content], "[Delegation Context]"
    assert_includes user_message[:content], "Called by: int_caller"
    assert_includes user_message[:content], "Analyze this"
  end

  def test_human_to_po_message_has_no_preamble
    path = create_test_po_file(@env_dir, name: "human_target")
    po = @runtime.load_prompt_object(path)

    po.receive("Hello from human", context: @runtime.context)

    user_message = @runtime.llm.calls.last[:messages].find { |m| m[:role] == :user }
    refute_includes user_message[:content], "[Delegation Context]"
    assert_equal "Hello from human", user_message[:content]
  end

  def test_delegation_preserves_original_message_content
    caller_path = create_test_po_file(@env_dir, name: "preserve_caller", description: "Preserves", capabilities: ["preserve_target"])
    target_path = create_test_po_file(@env_dir, name: "preserve_target", description: "Target")
    caller_po = @runtime.load_prompt_object(caller_path)
    target_po = @runtime.load_prompt_object(target_path)

    mock_llm = @runtime.llm
    mock_llm.queue_response(
      tool_calls: [
        PromptObjects::LLM::ToolCall.new(
          id: "call_002",
          name: "preserve_target",
          arguments: { "message" => "Specific task details here" }
        )
      ]
    )
    mock_llm.queue_response(content: "Done")
    mock_llm.queue_response(content: "Final")

    caller_po.receive("Start", context: @runtime.context)

    target_call = mock_llm.calls[1]
    user_message = target_call[:messages].find { |m| m[:role] == :user }
    assert_includes user_message[:content], "Specific task details here"
  end
end
