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
