#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-PO Workflow Example
#
# This example demonstrates advanced PromptObjects features:
# - Multiple POs working on a shared task
# - Message bus tracking inter-PO communication
# - Human-orchestrated workflow (human coordinates POs)
# - Each PO can use primitives (read_file, write_file, etc.)
#
# Note: Full autonomous PO-to-PO delegation (coordinator -> researcher -> writer)
# is supported but can hit edge cases with some LLM providers. This demo shows
# the human-orchestrated pattern which is more reliable.
#
# Prerequisites:
#   - Ollama running locally (http://localhost:11434)
#   - The gpt-oss:latest model pulled: ollama pull gpt-oss:latest
#
# Run with:
#   ./examples/03_po_delegation.rb

require "bundler/setup"
require_relative "../lib/prompt_objects"

objects_dir = File.join(__dir__, "poop/research_team")
data_dir = File.join(__dir__, "data")

puts <<~HEADER
  #{'=' * 70}
  PromptObjects Multi-PO Workflow Example
  #{'=' * 70}

  This demo shows multiple POs working together:
  - RESEARCHER gathers data from files
  - WRITER creates documents from that data
  - Human orchestrates the workflow
  - Message bus tracks all communication

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
  researcher = runtime.load_by_name("researcher")
  writer = runtime.load_by_name("writer")

  puts "Loaded POs:"

  runtime.loaded_objects.each do |name|
    po = runtime.get(name)
    caps = po.config["capabilities"]&.join(", ") || "none"

    puts "  - #{name}: [#{caps}]"
  end
  puts

  # Subscribe to message bus
  puts "-" * 70
  puts "Message Bus (live):"
  puts "-" * 70

  runtime.bus.subscribe do |entry|
    time = entry[:timestamp].strftime("%H:%M:%S")
    from = entry[:from].to_s.split("--").last || entry[:from]
    to = entry[:to].to_s.split("--").last || entry[:to]
    puts "  [#{time}] #{from} -> #{to}"
    msg = entry[:message].to_s.gsub(/\s+/, " ").strip
    if msg.length > 60
      puts "           #{msg[0, 60]}..."
    else
      puts "           #{msg}"
    end
  end

  puts

  context = runtime.context

  # Step 1: Have researcher gather information from project.json
  puts "=" * 70
  puts "STEP 1: Researcher gathers data"
  puts "=" * 70
  puts

  project_file = File.join(data_dir, "project.json")
  research_task = <<~TASK
    Please read the file #{project_file} and provide a summary of the
    project information you find. Use your think capability to reason
    about what's important, then read the file and summarize.
  TASK

  puts "Human -> Researcher: #{research_task[0, 60]}..."
  puts
  research_result = researcher.receive(research_task, context: context)
  puts
  puts "Researcher's findings:"
  puts research_result
  puts

  # Step 2: Have writer create a document based on the research
  puts "=" * 70
  puts "STEP 2: Writer creates announcement"
  puts "=" * 70
  puts

  write_task = <<~TASK
    Based on these research findings, create a brief markdown announcement:

    #{research_result}

    Return the complete markdown document. The announcement should be
    professional and highlight the key features. Use proper markdown
    formatting with a title and bullet points.
  TASK

  puts "Human -> Writer: Create announcement from research..."
  puts

  announcement_content = writer.receive(write_task, context: context)

  puts
  puts "Writer's response:"
  puts announcement_content
  puts

  # Save the generated document
  announcement_file = File.join(data_dir, "announcement.md")
  File.write(announcement_file, announcement_content)
  puts "Saved announcement to: #{announcement_file}"
  puts

  # Show workflow summary
  puts "=" * 70
  puts "Workflow Summary:"
  puts "=" * 70

  messages = runtime.bus.log

  participants = messages.flat_map { |m| [m[:from], m[:to]] }.uniq.compact

  puts "Participants: #{participants.map { |p| p.to_s.split('--').last }.uniq.join(', ')}"
  puts "Total messages: #{messages.length}"
  puts
  puts "Conversation lengths:"
  puts "  Researcher: #{researcher.history.length} messages"
  puts "  Writer: #{writer.history.length} messages"

rescue PromptObjects::Error => e
  puts "Error: #{e.message}"
  puts
  puts "Ensure Ollama is running with gpt-oss:latest model."
  puts "  ollama pull gpt-oss:latest"
  puts "  ollama serve"
end
