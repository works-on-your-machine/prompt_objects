# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to pause and ask the human a question.
    # For now this is synchronous (blocking). In Phase 5 with the TUI,
    # this will become async with a notification queue.
    class AskHuman < Primitive
      def name
        "ask_human"
      end

      def description
        "Pause and ask the human a question. Use this when you need confirmation, clarification, or input."
      end

      def parameters
        {
          type: "object",
          properties: {
            question: {
              type: "string",
              description: "The question to ask the human"
            },
            options: {
              type: "array",
              items: { type: "string" },
              description: "Optional list of choices to present"
            }
          },
          required: ["question"]
        }
      end

      def receive(message, context:)
        question = message[:question] || message["question"]
        options = message[:options] || message["options"]

        # In TUI mode, use the human queue (non-blocking for UI)
        if context.tui_mode && context.human_queue
          return receive_tui(question, options, context)
        end

        # REPL mode - use stdin directly
        receive_repl(question, options, context)
      end

      private

      def receive_tui(question, options, context)
        # Queue the request and wait for response
        request = context.human_queue.enqueue(
          capability: context.current_capability,
          question: question,
          options: options
        )

        # Log to message bus
        context.bus.publish(
          from: context.current_capability,
          to: "human",
          message: "[waiting] #{question}"
        )

        # Block this thread until human responds via UI
        response = request.wait_for_response

        # Log the response
        context.bus.publish(
          from: "human",
          to: context.current_capability,
          message: response
        )

        response
      end

      def receive_repl(question, options, context)
        puts
        puts "┌─ #{context.current_capability} asks ──────────────────────────────────┐"
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
