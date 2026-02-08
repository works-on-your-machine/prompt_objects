# frozen_string_literal: true

module PromptObjects
  module LLM
    # Normalized response from an LLM API call.
    # Wraps provider-specific responses into a common interface.
    class Response
      attr_reader :content, :tool_calls, :raw, :usage

      def initialize(content:, tool_calls: [], raw: nil, usage: nil)
        @content = content
        @tool_calls = tool_calls
        @raw = raw
        @usage = usage  # { input_tokens:, output_tokens:, model:, provider: }
      end

      # Check if the response includes tool calls.
      # @return [Boolean]
      def tool_calls?
        !@tool_calls.empty?
      end
    end

    # Represents a single tool call from the LLM.
    # Supports both method access (.id) and hash access ([:id]) for compatibility
    # with code that may receive either ToolCall objects or Hashes from the DB.
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        @arguments = arguments
      end

      # Allow hash-style access for compatibility with code expecting Hashes
      def [](key)
        case key.to_sym
        when :id then @id
        when :name then @name
        when :arguments then @arguments
        end
      end

      # Convert to a plain Hash (for serialization)
      def to_h
        { id: @id, name: @name, arguments: @arguments }
      end

      # Create a ToolCall from a Hash (for deserialization)
      def self.from_hash(hash)
        return hash if hash.is_a?(ToolCall)

        new(
          id: hash[:id] || hash["id"],
          name: hash[:name] || hash["name"],
          arguments: hash[:arguments] || hash["arguments"] || {}
        )
      end
    end
  end
end
