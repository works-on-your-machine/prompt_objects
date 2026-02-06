# frozen_string_literal: true

require_relative "../test_helper"

class CustomPrimitivesTest < PromptObjectsTest
  def setup
    super
    @env_dir = track_temp_dir(create_temp_env(name: "primitives_test"))
    FileUtils.mkdir_p(File.join(@env_dir, "primitives"))
  end

  # Helper: write a valid primitive .rb file to the env's primitives/ dir
  def write_primitive(name:, return_value: '"ok"', description: "Test primitive")
    class_name = name.split("_").map(&:capitalize).join
    code = <<~RUBY
      # frozen_string_literal: true

      module PromptObjects
        module Primitives
          class #{class_name} < Primitive
            def name
              "#{name}"
            end

            def description
              "#{description}"
            end

            def parameters
              { type: "object", properties: {}, required: [] }
            end

            def receive(message, context:)
              #{return_value}
            end
          end
        end
      end
    RUBY
    path = File.join(@env_dir, "primitives", "#{name}.rb")
    File.write(path, code)
    path
  end

  def test_loads_custom_primitives_on_startup
    write_primitive(name: "my_tool")
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    assert runtime.registry.get("my_tool"), "Custom primitive should be registered"
    assert_equal "my_tool", runtime.registry.get("my_tool").name
  end

  def test_loads_multiple_custom_primitives
    write_primitive(name: "tool_alpha")
    write_primitive(name: "tool_beta")
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    assert runtime.registry.get("tool_alpha"), "tool_alpha should be registered"
    assert runtime.registry.get("tool_beta"), "tool_beta should be registered"
  end

  def test_broken_primitive_warns_but_does_not_crash
    # Write a valid primitive
    write_primitive(name: "good_tool")

    # Write a broken primitive (syntax error)
    broken_path = File.join(@env_dir, "primitives", "bad_tool.rb")
    File.write(broken_path, "module PromptObjects; module Primitives; class BadTool < end; end; end")

    # Environment should start successfully despite broken primitive
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)
    assert runtime, "Runtime should initialize despite broken primitive"

    # Good primitive should still be loaded
    assert runtime.registry.get("good_tool"), "Valid primitive should still load"

    # Bad primitive should NOT be in registry
    refute runtime.registry.get("bad_tool"), "Broken primitive should not be registered"
  end

  def test_custom_primitives_coexist_with_stdlib
    write_primitive(name: "custom_tool")
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    # Stdlib primitives still present
    assert runtime.registry.get("read_file"), "read_file stdlib should be registered"
    assert runtime.registry.get("list_files"), "list_files stdlib should be registered"
    assert runtime.registry.get("write_file"), "write_file stdlib should be registered"
    assert runtime.registry.get("http_get"), "http_get stdlib should be registered"

    # Custom primitive also present
    assert runtime.registry.get("custom_tool"), "Custom primitive should be registered"
  end

  def test_no_primitives_dir_is_fine
    FileUtils.rm_rf(File.join(@env_dir, "primitives"))
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    # Should start fine with just stdlib
    assert runtime.registry.get("read_file"), "Stdlib should still work without primitives dir"
  end

  def test_empty_primitives_dir_is_fine
    # primitives/ dir exists but is empty (created in setup)
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    assert runtime.registry.get("read_file"), "Stdlib should work with empty primitives dir"
  end

  def test_custom_primitive_is_callable
    write_primitive(name: "echo_tool", return_value: '"hello from echo"')
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    primitive = runtime.registry.get("echo_tool")
    assert primitive, "echo_tool should be registered"

    result = primitive.receive({}, context: runtime.context)
    assert_equal "hello from echo", result
  end

  def test_custom_primitive_available_to_po
    write_primitive(name: "special_tool")
    runtime = PromptObjects::Runtime.new(env_path: @env_dir, llm: MockLLM.new)

    # Create a PO that lists the custom primitive in its capabilities
    po_path = create_test_po_file(@env_dir, name: "tester", capabilities: ["special_tool"])
    po = runtime.load_prompt_object(po_path)

    # The PO should have access to the custom primitive
    assert_includes po.config["capabilities"], "special_tool"

    # The primitive should be resolvable from the registry
    resolved = runtime.registry.get("special_tool")
    assert resolved, "Custom primitive should be resolvable for PO"
    assert resolved.is_a?(PromptObjects::Primitive), "Should be a Primitive instance"
  end
end
