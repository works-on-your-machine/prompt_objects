#!/usr/bin/env ruby
# frozen_string_literal: true

# Research Team Example
#
# This example demonstrates advanced PromptObjects capabilities:
# - Multiple prompt objects with different specializations
# - Human-in-the-loop via ask_human capability
# - Internal reasoning via think capability
# - Message bus tracking all inter-capability communication
# - Multiple primitives: read_file, list_files
#
# Prerequisites:
#   - Ollama running locally (http://localhost:11434)
#   - The gpt-oss:latest model pulled: ollama pull gpt-oss:latest
#
# Run with:
#   ./examples/02_research_team.rb

require "bundler/setup"
require_relative "../lib/prompt_objects"

objects_dir = File.join(__dir__, "poop/research_team")
data_dir = File.join(__dir__, "data")

puts <<~HEADER
  #{'=' * 70}
  PromptObjects Research Team Example
  #{'=' * 70}

  This demo shows multiple prompt objects collaborating:
  - RESEARCHER: Gathers information from files
  - WRITER: Creates structured documents

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

  # Load team members
  puts "Loading team members..."

  researcher = runtime.load_by_name("researcher")
  writer = runtime.load_by_name("writer")

  puts "  - #{researcher.name}: #{researcher.description}"
  puts "  - #{writer.name}: #{writer.description}"
  puts

  # Subscribe to message bus
  puts "-" * 70
  puts "Message Bus (live):"
  puts "-" * 70

  runtime.bus.subscribe do |entry|
    time = entry[:timestamp].strftime("%H:%M:%S")
    from = entry[:from].to_s.split("--").last || entry[:from]
    to = entry[:to].to_s.split("--").last || entry[:to]
    msg = entry[:message].to_s[0, 60]
    msg += "..." if entry[:message].to_s.length > 60
    puts "  [#{time}] #{from} -> #{to}: #{msg}"
  end

  puts

  context = runtime.context

  # Demo 1: Researcher gathering information
  puts "=" * 70
  puts "DEMO 1: Researcher gathering information"
  puts "=" * 70
  puts

  puts "User: Please examine the files in #{data_dir} and summarize what you find."
  puts

  response = researcher.receive(
    "Please examine the files in #{data_dir} and summarize what you find. " \
    "Use your think capability to reason about what you're looking for, " \
    "then read the files and provide a summary.",
    context: context
  )

  puts
  puts "Researcher: #{response}"
  puts

  # Demo 2: Writer creating a document
  puts "=" * 70
  puts "DEMO 2: Writer creating a document"
  puts "=" * 70
  puts

  puts "User: Create a summary document based on the research findings."
  puts

  research_context = <<~CONTEXT
    Based on the following research findings, create a markdown summary document:

    The PromptObjects framework is a Ruby system where markdown files with
    LLM-backed behavior act as first-class autonomous entities. Key features:
    - Unified capability interface (primitives and prompt objects share the same API)
    - YAML frontmatter for configuration
    - Markdown body becomes the system prompt
    - Message bus tracks all communication
    - Human-in-the-loop for confirmations

    Return the complete markdown document. Keep it concise (under 200 words).
  CONTEXT

  summary_content = writer.receive(research_context, context: context)

  puts
  puts "Writer: #{summary_content}"
  puts

  # Save the generated document
  output_file = File.join(data_dir, "generated_summary.md")
  File.write(output_file, summary_content)
  puts "Saved summary to: #{output_file}"
  puts

  # Show message bus history
  puts "=" * 70
  puts "Message Bus History (last 10 entries):"
  puts "=" * 70
  puts runtime.bus.format_log(10)
  puts

  # Show conversation histories
  puts "=" * 70
  puts "Conversation Histories:"
  puts "=" * 70

  [researcher, writer].each do |po|
    puts
    puts "#{po.name.upcase} (#{po.history.length} messages):"

    po.history.each_with_index do |msg, i|
      role = msg[:role].to_s.capitalize.ljust(10)
      content = msg[:content]&.to_s&.slice(0, 60) || "(tool calls)"
      content += "..." if (msg[:content]&.to_s&.length || 0) > 60

      puts "  #{i + 1}. [#{role}] #{content}"
    end
  end

rescue PromptObjects::Error => e
  puts "Error: #{e.message}"
  puts
  puts "Make sure Ollama is running and gpt-oss:latest is available:"
  puts "  ollama pull gpt-oss:latest"
  puts "  ollama serve"
end
