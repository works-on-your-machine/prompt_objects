# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # Get detailed information about a prompt object
      class InspectPO < ::MCP::Tool
        tool_name "inspect_po"
        description "Get detailed information about a prompt object including its configuration, capabilities, and prompt body"

        input_schema(
          type: "object",
          properties: {
            po_name: {
              type: "string",
              description: "Name of the prompt object to inspect"
            }
          },
          required: %w[po_name]
        )

        def self.call(po_name:, server_context:)
          env = server_context[:env]

          po = env.registry.get(po_name)
          unless po.is_a?(PromptObjects::PromptObject)
            return ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
            }])
          end

          info = po.to_inspect_hash(registry: env.registry)

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.pretty_generate(info)
          }])
        end
      end
    end
  end
end
