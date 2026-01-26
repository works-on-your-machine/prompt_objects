#!/usr/bin/env ruby
# frozen_string_literal: true

# Research Team Example
#
# Demonstrates:
# - Multiple prompt objects with different specializations
# - Message bus tracking inter-capability communication
# - Chaining PO outputs (research -> writing)

require_relative "setup"
include Examples

box "PromptObjects Research Team Example"

run_demo do
  runtime = create_runtime(objects: objects_dir("research_team"))

  researcher = runtime.load_by_name("researcher")
  writer = runtime.load_by_name("writer")

  show_loaded_pos(runtime)

  divider "Message Bus (live)"
  subscribe_to_bus(runtime, compact: true)
  puts

  context = runtime.context

  # Researcher gathers information
  box "DEMO 1: Researcher gathering information"

  project_file = File.join(data_dir, "project.json")
  puts "User: Please read #{project_file} and summarize."
  puts

  response = researcher.receive(
    "Please read the file #{project_file} and summarize the project information.",
    context: context
  )

  puts
  puts "Researcher: #{response}"
  puts

  # Writer creates a document using write_file
  box "DEMO 2: Writer creating a document"

  output_file = File.join(data_dir, "generated_summary.md")
  puts "User: Create a summary document and save it to #{output_file}."
  puts

  writer_response = writer.receive(<<~TASK, context: context)
    Based on the following research findings, create a markdown summary document
    and save it to: #{output_file}

    The PromptObjects framework is a Ruby system where markdown files with
    LLM-backed behavior act as first-class autonomous entities. Key features:
    - Unified capability interface (primitives and prompt objects share the same API)
    - YAML frontmatter for configuration
    - Markdown body becomes the system prompt
    - Message bus tracks all communication
    - Human-in-the-loop for confirmations

    Use write_file to save the document. Keep it concise (under 200 words).
  TASK

  puts
  puts "Writer: #{writer_response}"
  puts

  # Verify the file was created
  if File.exist?(output_file)
    box "Generated Summary"
    puts File.read(output_file)
  end

  # Show message bus history
  box "Message Bus History"
  puts runtime.bus.format_log(10)
  puts

  # Show conversation histories
  box "Conversation Histories"
  [researcher, writer].each do |po|
    show_history(po)
    puts
  end
end
