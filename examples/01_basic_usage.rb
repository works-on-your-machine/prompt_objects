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

objects_dir = File.join(__dir__, "poop")
data_dir = File.join(__dir__, "data")

puts <<~HEADER
  #{'=' * 60}
  PromptObjects Basic Example
  #{'=' * 60}

  Objects directory: #{objects_dir}
  Data directory: #{data_dir}
  Provider: ollama
  Model: gpt-oss:latest

HEADER

begin
  runtime = PromptObjects::Runtime.new(
    objects_dir: objects_dir,
    provider: "ollama",
    model: "gpt-oss:latest"
  )

  assistant = runtime.load_by_name("assistant")

  puts "Loaded: #{assistant.name}"
  puts "Description: #{assistant.description}"
  puts "Capabilities: #{assistant.config['capabilities'].join(', ')}"
  puts
  puts "-" * 60
  puts "Starting conversation..."
  puts "-" * 60
  puts

  context = runtime.context

  # Example 1: Simple greeting
  puts "User: Hello! What can you help me with?"

  response = assistant.receive("Hello! What can you help me with?", context: context)

  puts "Assistant: #{response}"
  puts

  # Example 2: List files (uses list_files primitive)
  puts "User: Can you list the files in #{data_dir}?"

  response = assistant.receive("Can you list the files in #{data_dir}?", context: context)

  puts "Assistant: #{response}"
  puts

  # Example 3: Read a file (uses read_file primitive)
  greeting_file = File.join(data_dir, "greeting.txt")
  puts "User: What's in #{greeting_file}?"

  response = assistant.receive("What's in the file #{greeting_file}?", context: context)

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
end
