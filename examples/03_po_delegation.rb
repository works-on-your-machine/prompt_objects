#!/usr/bin/env ruby
# frozen_string_literal: true

# PO-to-PO Delegation Example
#
# Demonstrates:
# - Prompt objects calling other prompt objects as capabilities
# - Coordinator delegating to researcher and writer
# - Autonomous multi-step workflows
# - Message bus tracking inter-PO communication

require_relative "setup"
include Examples

box "PromptObjects PO-to-PO Delegation Example"

run_demo do
  runtime = create_runtime(objects: objects_dir("research_team"))

  # Load all three POs - they must be registered for delegation to work
  coordinator = runtime.load_by_name("coordinator")
  runtime.load_by_name("researcher")
  runtime.load_by_name("writer")

  show_loaded_pos(runtime)

  divider "Message Bus (live)"
  subscribe_to_bus(runtime)
  puts

  context = runtime.context

  # Give coordinator a complex task - it should delegate autonomously
  box "Coordinator receives a complex task"

  project_file = File.join(data_dir, "project.json")
  output_file = File.join(data_dir, "announcement.md")

  puts "Human -> Coordinator: Research the project and create an announcement."
  puts

  result = coordinator.receive(<<~TASK, context: context)
    Please complete this multi-step task:

    1. Ask the researcher to read #{project_file} and summarize it
    2. Ask the writer to create an announcement based on the research
       and save it to #{output_file}

    Coordinate the workflow and report back when complete.
  TASK

  puts
  puts "Coordinator's report:"
  puts result
  puts

  # Show message bus to see the delegation flow
  box "Message Bus History (showing PO-to-PO calls)"
  puts runtime.bus.format_log(15)
  puts

  # Verify the file was created
  if File.exist?(output_file)
    box "Generated Announcement"
    puts File.read(output_file)
  end
end
