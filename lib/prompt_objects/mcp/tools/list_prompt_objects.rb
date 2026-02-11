# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # List all loaded prompt objects with their current state
      class ListPromptObjects < ::MCP::Tool
        tool_name "list_prompt_objects"
        description "List all loaded prompt objects with their names, descriptions, and current state"

        input_schema(
          type: "object",
          properties: {}
        )

        def self.call(server_context:, **_args)
          env = server_context[:env]

          pos = env.registry.prompt_objects.map do |po|
            {
              name: po.name,
              description: po.description,
              state: po.state || :idle,
              capabilities: po.config["capabilities"] || []
            }
          end

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.pretty_generate(pos)
          }])
        end
      end
    end
  end
end
