# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to list all available capabilities in the registry.
    # This helps POs discover what tools exist.
    class ListCapabilities < Primitives::Base
      description "List all available capabilities (primitives and prompt objects) in the system. Useful for discovering what tools exist before creating new ones."
      param :type, desc: "Filter by type: 'all', 'primitives', or 'prompt_objects'. Default is 'all'."

      def execute(type: "all")
        capabilities = case type.to_s
        when "primitives"
          registry.primitives
        when "prompt_objects"
          registry.prompt_objects
        else
          registry.all
        end

        if capabilities.empty?
          return "No capabilities found."
        end

        lines = capabilities.map do |cap|
          if cap.is_a?(Class)
            # RubyLLM::Tool class
            "[Primitive] #{extract_name(cap)}: #{cap.description}"
          elsif cap.is_a?(PromptObject)
            "[PO] #{cap.name}: #{cap.description}"
          else
            "[Primitive] #{cap.name}: #{cap.description}"
          end
        end

        "Available capabilities:\n#{lines.map { |l| "- #{l}" }.join("\n")}"
      end

      private

      def extract_name(cap)
        if cap.respond_to?(:tool_name)
          cap.tool_name
        else
          cap.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end
      end
    end
  end
end
