# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # Respond to a pending human request
      class RespondToRequest < ::MCP::Tool
        tool_name "respond_to_request"
        description "Respond to a pending human request from a prompt object. This unblocks the PO that asked the question."

        input_schema(
          type: "object",
          properties: {
            request_id: {
              type: "string",
              description: "The ID of the pending request (from get_pending_requests)"
            },
            response: {
              type: "string",
              description: "Your response to the question"
            }
          },
          required: %w[request_id response]
        )

        def self.call(request_id:, response:, server_context:)
          env = server_context[:env]
          queue = env.human_queue

          # Find the request first to give better error messages
          request = queue.all_pending.find { |r| r.id == request_id }

          unless request
            return ::MCP::Tool::Response.new([{
              type: "text",
              text: JSON.generate({
                error: "Request not found",
                request_id: request_id,
                hint: "Use get_pending_requests to see available requests"
              })
            }])
          end

          # Respond (this unblocks the waiting thread)
          queue.respond(request_id, response)

          # Log to message bus
          env.bus.publish(
            from: "mcp_client",
            to: request.capability,
            message: "[response to ask_human] #{response}"
          )

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.generate({
              success: true,
              request_id: request_id,
              capability: request.capability,
              question: request.question,
              response: response
            })
          }])
        end
      end
    end
  end
end
