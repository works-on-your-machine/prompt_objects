#!/usr/bin/env ruby
# frozen_string_literal: true

# Multi-PO Workflow Example
#
# Demonstrates:
# - Multiple POs working on a shared task
# - Human-orchestrated workflow (human coordinates POs)
# - Message bus tracking inter-PO communication
# - Chaining PO outputs (research -> writing)

require_relative "setup"
include Examples

box "PromptObjects Multi-PO Workflow Example"

run_demo do
  runtime = create_runtime(objects: objects_dir("research_team"))

  researcher = runtime.load_by_name("researcher")
  writer = runtime.load_by_name("writer")

  show_loaded_pos(runtime)

  divider "Message Bus (live)"
  subscribe_to_bus(runtime)
  puts

  context = runtime.context

  # Step 1: Researcher gathers data
  box "STEP 1: Researcher gathers data"

  project_file = File.join(data_dir, "project.json")

  puts "Human -> Researcher: Read #{project_file} and summarize..."
  puts

  research_result = researcher.receive(<<~TASK, context: context)
    Please read the file #{project_file} and summarize the project information.
  TASK

  puts
  puts "Researcher's findings:"
  puts research_result
  puts

  # Step 2: Writer creates announcement using write_file
  box "STEP 2: Writer creates announcement"

  announcement_file = File.join(data_dir, "announcement.md")
  puts "Human -> Writer: Create announcement and save to #{announcement_file}..."
  puts

  writer_response = writer.receive(<<~TASK, context: context)
    Based on these research findings, create a brief markdown announcement
    and save it to: #{announcement_file}

    #{research_result}

    Use write_file to save the announcement. The announcement should be
    professional and highlight the key features. Use proper markdown
    formatting with a title and bullet points.
  TASK

  puts
  puts "Writer's response:"
  puts writer_response
  puts

  # Workflow summary
  box "Workflow Summary"

  messages = runtime.bus.log
  participants = messages.flat_map { |m| [m[:from], m[:to]] }.compact
  participants = participants.map { |p| simplify_name(p) }.uniq

  puts "Participants: #{participants.join(', ')}"
  puts "Total messages: #{messages.length}"
  puts
  puts "Conversation lengths:"
  puts "  Researcher: #{researcher.history.length} messages"
  puts "  Writer: #{writer.history.length} messages"
end
