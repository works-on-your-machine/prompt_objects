# frozen_string_literal: true

# Common setup and utilities for PromptObjects examples.
# Reduces boilerplate so demos can focus on actual PromptObjects functionality.

require "bundler/setup"
require_relative "../lib/prompt_objects"

module Examples
  WIDTH = 70
  PROVIDER = "ollama"
  MODEL = "devstral:latest"  # Fast and good tool call support

  module_function

  # Path to the shared data directory
  def data_dir
    File.join(__dir__, "data")
  end

  # Path to objects directory, with optional subdirectory
  def objects_dir(subdir = nil)
    base = File.join(__dir__, "poop")
    subdir ? File.join(base, subdir) : base
  end

  # Output a title in a box of = characters
  def box(title)
    sep = "=" * (title.size + 6)
    puts sep
    puts "== " + title + " =="
    puts sep
    puts
  end

  # Output a section divider with - characters
  def divider(title = nil)
    puts "-" * WIDTH
    puts title if title
    puts "-" * WIDTH
    puts
  end

  # Create a runtime with standard configuration
  def create_runtime(objects:)
    PromptObjects::Runtime.new(
      objects_dir: objects,
      provider: PROVIDER,
      model: MODEL
    )
  end

  # Subscribe to message bus with formatted output
  def subscribe_to_bus(runtime, compact: false)
    runtime.bus.subscribe do |entry|
      time = entry[:timestamp].strftime("%H:%M:%S")
      from = simplify_name(entry[:from])
      to = simplify_name(entry[:to])
      msg = entry[:message].to_s.gsub(/\s+/, " ").strip
      msg = truncate(msg, 60)

      if compact
        puts "  [#{time}] #{from} -> #{to}: #{msg}"
      else
        puts "  [#{time}] #{from} -> #{to}"
        puts "           #{msg}"
      end
    end
  end

  # Display conversation history for a PO
  def show_history(po, max_content: 60)
    puts "#{po.name.upcase} (#{po.history.length} messages):"

    po.history.each_with_index do |msg, i|
      role = msg[:role].to_s.capitalize.ljust(10)
      content = msg[:content]&.to_s || "(tool calls)"
      content = truncate(content, max_content)
      puts "  #{i + 1}. [#{role}] #{content}"
    end
  end

  # Display loaded POs with their capabilities
  def show_loaded_pos(runtime)
    puts "Loaded POs:"
    runtime.loaded_objects.each do |name|
      po = runtime.get(name)
      caps = po.config["capabilities"]&.join(", ") || "none"
      puts "  - #{name}: [#{caps}]"
    end
    puts
  end

  # Truncate string with ellipsis
  def truncate(str, max)
    str.length > max ? "#{str[0, max]}..." : str
  end

  # Send a message and display the response
  # Usage: send_message("Hello!") { |msg| po.receive(msg, context: ctx) }
  def send_message(message)
    puts "User: #{message}"
    response = yield(message)
    puts "Assistant: #{response}"
    puts
    response
  end

  # Simplify tool names (remove module prefixes)
  def simplify_name(name)
    name.to_s.split("--").last || name
  end

  # Run a demo block with standard error handling
  def run_demo
    yield
  rescue PromptObjects::Error => e
    puts "PromptObjects Error: #{e.message}"
    puts
    puts "Make sure Ollama is running with #{MODEL}:"
    puts "  ollama pull #{MODEL}"
    puts "  ollama serve"
  rescue RubyLLM::ServerError => e
    puts "LLM Error: #{e.message}"
    puts
    puts "This may be an Ollama/RubyLLM compatibility issue with tool calls."
    puts "Try using a different model or provider."
  rescue StandardError => e
    puts "Error: #{e.class}: #{e.message}"
    puts e.backtrace.first(5).join("\n")
  end
end
