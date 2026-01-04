# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # Send a message to a prompt object and get its response
      class SendMessage < ::MCP::Tool
        tool_name "send_message"
        description "Send a message to a prompt object. The PO will process it (potentially calling tools) and return a response."

        input_schema(
          type: "object",
          properties: {
            po_name: {
              type: "string",
              description: "Name of the prompt object to message"
            },
            message: {
              type: "string",
              description: "The message to send"
            }
          },
          required: %w[po_name message]
        )

        def self.call(po_name:, message:, server_context:)
          env = server_context[:env]
          context = server_context[:context]

          po = env.registry.get(po_name)
          unless po.is_a?(PromptObjects::PromptObject)
            return ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ error: "Prompt object '#{po_name}' not found" })
            }])
          end

          # Log to message bus
          env.bus.publish(from: "mcp_client", to: po_name, message: message)

          # Set context for this interaction
          context.current_capability = po_name
          po.state = :working

          begin
            response = po.receive(message, context: context)
            po.state = :idle

            # Log response
            env.bus.publish(from: po_name, to: "mcp_client", message: response)

            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({
                po_name: po_name,
                response: response,
                history_length: po.history.length
              })
            }])
          rescue StandardError => e
            po.state = :idle
            ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({ error: e.message, backtrace: e.backtrace.first(5) })
            }])
          end
        end
      end
    end
  end
end
