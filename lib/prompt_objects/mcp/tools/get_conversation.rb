# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # Get conversation history for a prompt object
      class GetConversation < ::MCP::Tool
        tool_name "get_conversation"
        description "Get the conversation history for a prompt object"

        input_schema(
          type: "object",
          properties: {
            po_name: {
              type: "string",
              description: "Name of the prompt object"
            },
            limit: {
              type: "integer",
              description: "Maximum number of messages to return (default: all)"
            }
          },
          required: %w[po_name]
        )

        def self.call(po_name:, limit: nil, server_context:)
          env = server_context[:env]

          po = env.registry.get(po_name)
          unless po.is_a?(PromptObjects::PromptObject)
            return ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
            }])
          end

          history = po.history.map do |msg|
            {
              role: msg[:role].to_s,
              content: msg[:content],
              tool_calls: msg[:tool_calls]&.map { |tc| { name: tc.name, arguments: tc.arguments } }
            }.compact
          end

          history = history.last(limit) if limit

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.pretty_generate({
              po_name: po_name,
              message_count: history.length,
              history: history
            })
          }])
        end
      end
    end
  end
end
