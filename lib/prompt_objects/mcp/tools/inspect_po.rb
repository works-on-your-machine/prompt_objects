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

          # Categorize capabilities
          declared_caps = po.config["capabilities"] || []
          universal_caps = PromptObjects::UNIVERSAL_CAPABILITIES

          # Resolve which are POs vs primitives
          delegates = []
          primitives = []

          declared_caps.each do |cap_name|
            cap = env.registry.get(cap_name)
            if cap.is_a?(PromptObjects::PromptObject)
              delegates << cap_name
            elsif cap.is_a?(PromptObjects::Primitive)
              primitives << cap_name
            end
          end

          info = {
            name: po.name,
            description: po.description,
            state: po.state || :idle,
            config: po.config,
            capabilities: {
              universal: universal_caps,
              primitives: primitives,
              delegates: delegates,
              all_declared: declared_caps
            },
            prompt_body: po.body,
            history_length: po.history.length
          }

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.pretty_generate(info)
          }])
        end
      end
    end
  end
end
