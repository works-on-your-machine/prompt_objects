# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability for internal reasoning.
    # Thoughts are logged to the message bus but displayed differently (dimmed).
    # This helps POs "think out loud" without cluttering the conversation.
    class Think < Primitives::Base
      description "Internal reasoning step. Use this to think through a problem before acting. The thought is logged but not shown prominently to the human."
      param :thought, desc: "Your internal reasoning or thought process"

      def execute(thought:)
        cap_name = current_capability || "assistant"

        # Display dimmed (using ANSI codes)
        puts "\e[2m    💭 #{cap_name} thinks: #{thought}\e[0m"

        # Return acknowledgment
        "Thought recorded."
      end
    end
  end
end
