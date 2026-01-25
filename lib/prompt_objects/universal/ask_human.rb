# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to pause and ask the human a question.
    # For now this is synchronous (blocking). In Phase 5 with the TUI,
    # this will become async with a notification queue.
    class AskHuman < Primitives::Base
      description "Pause and ask the human a question. Use this when you need confirmation, clarification, or input."
      param :question, desc: "The question to ask the human"
      param :options, desc: "Optional list of choices to present (comma-separated)"

      def execute(question:, options: nil)
        # Parse options if provided as string
        options_array = parse_options(options)

        # In TUI mode, use the human queue (non-blocking for UI)
        if context&.tui_mode && human_queue
          return execute_tui(question, options_array)
        end

        # REPL mode - use stdin directly
        execute_repl(question, options_array)
      end

      private

      def parse_options(options)
        return nil if options.nil?
        return options if options.is_a?(Array)

        # Parse comma-separated string
        options.to_s.split(",").map(&:strip)
      end

      def execute_tui(question, options)
        # Queue the request and wait for response
        request = human_queue.enqueue(
          capability: current_capability,
          question: question,
          options: options
        )

        # Log to message bus
        message_bus&.publish(
          from: current_capability,
          to: "human",
          message: "[waiting] #{question}"
        )

        # Block this thread until human responds via UI
        response = request.wait_for_response

        # Log the response
        message_bus&.publish(
          from: "human",
          to: current_capability,
          message: response
        )

        response
      end

      def execute_repl(question, options)
        cap_name = current_capability || "assistant"

        puts
        puts "┌─ #{cap_name} asks ──────────────────────────────────┐"
        puts "│"
        puts "│  #{question}"
        puts "│"

        if options && !options.empty?
          options.each_with_index do |opt, i|
            puts "│  [#{i + 1}] #{opt}"
          end
          puts "│"
          puts "└──────────────────────────────────────────────────────────────┘"
          print "Your choice (1-#{options.length}): "

          choice = $stdin.gets&.chomp
          index = choice.to_i - 1

          if index >= 0 && index < options.length
            options[index]
          else
            choice  # Return raw input if not a valid index
          end
        else
          puts "└──────────────────────────────────────────────────────────────┘"
          print "Your answer: "
          $stdin.gets&.chomp || ""
        end
      end
    end
  end
end
