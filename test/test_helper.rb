# frozen_string_literal: true

require "bundler/setup"
require "minitest/autorun"
require "minitest/pride"
require "fileutils"
require "tmpdir"
require "net/http"

# Load the library
require_relative "../lib/prompt_objects"

# Test model for Ollama - use a model that supports tool calling
TEST_OLLAMA_MODEL = ENV.fetch("TEST_OLLAMA_MODEL", "mistral:latest")

module TestHelpers
  # Check if Ollama is available for testing
  def ollama_available?
    uri = URI("http://localhost:11434/api/tags")
    response = Net::HTTP.get_response(uri)
    response.is_a?(Net::HTTPSuccess)
  rescue Errno::ECONNREFUSED, Errno::ECONNRESET, SocketError
    false
  end

  # Skip test if Ollama is not available
  def skip_unless_ollama
    skip "Ollama not available - skipping LLM integration test" unless ollama_available?
  end

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

      You are a test prompt object. Keep your responses extremely brief - one sentence max.
      When asked to read a file, just acknowledge the request briefly.
    MD

    path = File.join(dir, "objects", "#{name}.md")
    File.write(path, content)
    path
  end

  # Create a runtime with real Ollama LLM for testing
  def create_test_runtime(env_path: nil, objects_dir: nil)
    llm = PromptObjects::LLM::Client.new(provider: "ollama", model: TEST_OLLAMA_MODEL)

    if env_path
      PromptObjects::Runtime.new(env_path: env_path, llm: llm)
    elsif objects_dir
      PromptObjects::Runtime.new(objects_dir: objects_dir, llm: llm)
    else
      dir = create_temp_env
      PromptObjects::Runtime.new(env_path: dir, llm: llm)
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
