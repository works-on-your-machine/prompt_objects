# frozen_string_literal: true

module PromptObjects
  module LLM
    # Normalized response from an LLM API call.
    # Wraps provider-specific responses into a common interface.
    class Response
      attr_reader :content, :tool_calls, :raw

      def initialize(content:, tool_calls: [], raw: nil)
        @content = content
        @tool_calls = tool_calls
        @raw = raw
      end

      # Check if the response includes tool calls.
      # @return [Boolean]
      def tool_calls?
        !@tool_calls.empty?
      end
    end

    # Represents a single tool call from the LLM.
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        @arguments = arguments
      end
    end
  end
end
