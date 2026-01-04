# frozen_string_literal: true

module PromptObjects
  module MCP
    module Tools
      # Get all pending human requests from the queue
      class GetPendingRequests < ::MCP::Tool
        tool_name "get_pending_requests"
        description "Get all pending human requests across all prompt objects. These are questions POs have asked that await human response."

        input_schema(
          type: "object",
          properties: {
            po_name: {
              type: "string",
              description: "Optional: filter to requests from a specific PO"
            }
          },
          required: []
        )

        def self.call(po_name: nil, server_context:)
          env = server_context[:env]
          queue = env.human_queue

          requests = if po_name
                       queue.pending_for(po_name)
                     else
                       queue.all_pending
                     end

          formatted = requests.map do |req|
            {
              id: req.id,
              capability: req.capability,
              question: req.question,
              options: req.options,
              age: req.age_string,
              created_at: req.created_at.iso8601
            }
          end

          ::MCP::Tool::Response.new([{
            type: "text",
            text: JSON.pretty_generate({
              count: formatted.length,
              requests: formatted
            })
          }])
        end
      end
    end
  end
end
