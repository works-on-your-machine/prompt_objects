# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "minitest/pride"
require "fileutils"
require "tmpdir"

# Load the library
require_relative "../lib/prompt_objects"

module TestHelpers
  # Create an in-memory session store for fast, isolated tests
  def create_memory_store
    PromptObjects::Session::Store.new(":memory:")
  end

  # Create a temporary environment directory with manifest
  def create_temp_env(name: "test_env")
    dir = Dir.mktmpdir("prompt_objects_test_")
    objects_dir = File.join(dir, "objects")
    FileUtils.mkdir_p(objects_dir)

    # Create manifest
    manifest = {
      "name" => name,
      "description" => "Test environment",
      "version" => "1.0.0",
      "created_at" => Time.now.iso8601
    }
    File.write(File.join(dir, "manifest.yml"), YAML.dump(manifest))

    dir
  end

  # Clean up a temporary environment
  def cleanup_temp_env(dir)
    FileUtils.rm_rf(dir) if dir && Dir.exist?(dir)
  end

  # Create a test prompt object markdown file
  def create_test_po_file(dir, name:, description: "Test PO", capabilities: [])
    content = <<~MD
      ---
      name: #{name}
      description: #{description}
      capabilities:
      #{capabilities.map { |c| "  - #{c}" }.join("\n")}
      ---

      # #{name.capitalize}

      You are a test prompt object.
    MD

    path = File.join(dir, "objects", "#{name}.md")
    File.write(path, content)
    path
  end

  # Create a runtime with mock LLM for testing
  def create_test_runtime(env_path: nil, objects_dir: nil)
    if env_path
      PromptObjects::Runtime.new(env_path: env_path, llm: MockLLM.new)
    elsif objects_dir
      PromptObjects::Runtime.new(objects_dir: objects_dir, llm: MockLLM.new)
    else
      dir = create_temp_env
      PromptObjects::Runtime.new(env_path: dir, llm: MockLLM.new)
    end
  end

  # Create a server context for MCP tool testing
  def create_mcp_context(runtime, connector: nil)
    {
      env: runtime,
      context: runtime.context(tui_mode: true),
      connector: connector
    }
  end
end

# Mock LLM adapter that returns predictable responses without API calls
class MockLLM
  attr_reader :calls

  def initialize(responses: [])
    @responses = responses
    @calls = []
    @call_index = 0
  end

  # Record the call and return a mock response
  # Matches the signature of LLM::Client#chat (returns a hash)
  def chat(system:, messages:, tools: [])
    @calls << { system: system, messages: messages, tools: tools }
    response = @responses[@call_index] || default_response
    @call_index += 1
    response
  end

  # Queue a specific response for the next call
  def queue_response(content: nil, tool_calls: [])
    @responses << { content: content, tool_calls: tool_calls }
  end

  # Reset call history
  def reset!
    @calls = []
    @call_index = 0
  end

  private

  def default_response
    { content: "Mock response from LLM", tool_calls: [] }
  end
end

# Mock MCP connector for testing
class MockConnector < PromptObjects::Connectors::Base
  def source_name
    "test"
  end

  def start
    @running = true
  end
end

# Base test class with helpers included
class PromptObjectsTest < Minitest::Test
  include TestHelpers

  def setup
    @temp_dirs = []
  end

  def teardown
    @temp_dirs.each { |dir| cleanup_temp_env(dir) }
  end

  # Track temp dirs for cleanup
  def track_temp_dir(dir)
    @temp_dirs << dir
    dir
  end
end
