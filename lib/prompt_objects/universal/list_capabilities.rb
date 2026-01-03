# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to list all available capabilities in the registry.
    # This helps POs discover what tools exist.
    class ListCapabilities < Primitive
      def name
        "list_capabilities"
      end

      def description
        "List all available capabilities (primitives and prompt objects) in the system. Useful for discovering what tools exist before creating new ones."
      end

      def parameters
        {
          type: "object",
          properties: {
            type: {
              type: "string",
              enum: ["all", "primitives", "prompt_objects"],
              description: "Filter by type. Default is 'all'."
            }
          },
          required: []
        }
      end

      def receive(message, context:)
        filter = message[:type] || message["type"] || "all"

        capabilities = case filter
        when "primitives"
          context.env.registry.primitives
        when "prompt_objects"
          context.env.registry.prompt_objects
        else
          context.env.registry.all
        end

        if capabilities.empty?
          return "No capabilities found."
        end

        lines = capabilities.map do |cap|
          type_label = cap.is_a?(PromptObject) ? "[PO]" : "[Primitive]"
          "- #{cap.name} #{type_label}: #{cap.description}"
        end

        "Available capabilities:\n#{lines.join("\n")}"
      end
    end
  end
end
