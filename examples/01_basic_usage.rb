#!/usr/bin/env ruby
# frozen_string_literal: true

# Basic PromptObjects Example
#
# Demonstrates:
# - Creating a runtime and loading a prompt object
# - Sending messages and receiving responses
# - Using primitives (list_files, read_file)

require_relative "setup"
include Examples

box "PromptObjects Basic Example"

run_demo do
  runtime = create_runtime(objects: objects_dir)
  assistant = runtime.load_by_name("assistant")

  puts "Loaded: #{assistant.name}"
  puts "Description: #{assistant.description}"
  puts "Capabilities: #{assistant.config['capabilities'].join(', ')}"
  puts

  divider "Conversation"

  context = runtime.context
  to_poop = ->(msg) { assistant.receive(msg, context: context) }

  send_message("Hello! What can you help me with?", &to_poop)
  send_message("Can you list the files in #{data_dir}?", &to_poop)
  send_message("What's in the file #{File.join(data_dir, 'greeting.txt')}?", &to_poop)

  divider "Conversation History"
  show_history(assistant, max_content: 100)
end
