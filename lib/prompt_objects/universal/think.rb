# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability for internal reasoning.
    # Thoughts are logged to the message bus but displayed differently (dimmed).
    # This helps POs "think out loud" without cluttering the conversation.
    class Think < Primitive
      def name
        "think"
      end

      def description
        "Internal reasoning step. Use this to think through a problem before acting. The thought is logged but not shown prominently to the human."
      end

      def parameters
        {
          type: "object",
          properties: {
            thought: {
              type: "string",
              description: "Your internal reasoning or thought process"
            }
          },
          required: ["thought"]
        }
      end

      def receive(message, context:)
        thought = message[:thought] || message["thought"]

        # Display dimmed (using ANSI codes)
        puts "\e[2m    💭 #{context.current_capability} thinks: #{thought}\e[0m"

        # Return acknowledgment
        "Thought recorded."
      end
    end
  end
end
