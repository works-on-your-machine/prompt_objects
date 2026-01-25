#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic PromptObjects Example
#
# This example demonstrates the core functionality of PromptObjects:
# - Creating a runtime from an objects directory
# - Loading a prompt object from a markdown file
# - Sending messages and receiving responses
# - Using tool calls (primitives)
#
# Prerequisites:
#   - Ollama running locally (http://localhost:11434)
#   - The gpt-oss:latest model pulled: ollama pull gpt-oss:latest
#
# Run with:
#   ./examples/01_basic_usage.rb

require "bundler/setup"
require_relative "../lib/prompt_objects"
require "tmpdir"
require "fileutils"

# Use the poop directory which contains our prompt objects
objects_dir = File.join(__dir__, "poop")

# Create sample files in a temp directory for the assistant to work with
sample_dir = Dir.mktmpdir("prompt_objects_sample_")
File.write(File.join(sample_dir, "greeting.txt"), "Hello from PromptObjects!")
File.write(File.join(sample_dir, "info.txt"), "PromptObjects is a framework where markdown files act as autonomous LLM-backed entities.")

puts "=" * 60
puts "PromptObjects Basic Example"
puts "=" * 60
puts
puts "Objects directory: #{objects_dir}"
puts "Sample files: #{sample_dir}"
puts "Provider: ollama"
puts "Model: gpt-oss:latest"
puts

begin
  # Create the runtime using the objects directory
  runtime = PromptObjects::Runtime.new(
    objects_dir: objects_dir,
    provider: "ollama",
    model: "gpt-oss:latest"
  )

  # Load our assistant prompt object
  assistant = runtime.load_by_name("assistant")

  puts "Loaded prompt object: #{assistant.name}"
  puts "Description: #{assistant.description}"
  puts "Capabilities: #{assistant.config['capabilities'].join(', ')}"
  puts
  puts "-" * 60
  puts "Starting conversation..."
  puts "-" * 60
  puts

  # Create an execution context
  context = runtime.context

  # Example 1: Simple greeting
  puts "User: Hello! What can you help me with?"
  response = assistant.receive("Hello! What can you help me with?", context: context)
  puts "Assistant: #{response}"
  puts

  # Example 2: Ask to list files (uses list_files primitive)
  puts "User: Can you list the files in #{sample_dir}?"
  response = assistant.receive("Can you list the files in #{sample_dir}?", context: context)
  puts "Assistant: #{response}"
  puts

  # Example 3: Ask to read a file (uses read_file primitive)
  puts "User: What's in the greeting.txt file?"
  response = assistant.receive("What's in the file #{File.join(sample_dir, 'greeting.txt')}?", context: context)
  puts "Assistant: #{response}"
  puts

  puts "-" * 60
  puts "Conversation history:"
  puts "-" * 60
  assistant.history.each_with_index do |msg, i|
    role = msg[:role].to_s.capitalize
    content = msg[:content]&.to_s&.slice(0, 100)
    content += "..." if msg[:content]&.to_s&.length.to_i > 100
    puts "#{i + 1}. [#{role}] #{content || '(tool calls)'}"
  end

rescue PromptObjects::Error => e
  puts "Error: #{e.message}"
  puts
  puts "Make sure Ollama is running and gpt-oss:latest is available:"
  puts "  ollama pull gpt-oss:latest"
  puts "  ollama serve"
ensure
  # Clean up sample files
  FileUtils.rm_rf(sample_dir) if sample_dir && Dir.exist?(sample_dir)
  puts
  puts "Cleaned up sample files."
end
