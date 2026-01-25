# frozen_string_literal: true

module PromptObjects
  module LLM
    # Represents a single tool call from the LLM.
    # Supports both method access (.id) and hash access ([:id]) for compatibility.
    class ToolCall
      attr_reader :id, :name, :arguments

      def initialize(id:, name:, arguments:)
        @id = id
        @name = name
        @arguments = arguments || {}
      end

      def [](key)
        case key.to_sym
        when :id then @id
        when :name then @name
        when :arguments then @arguments
        end
      end

      def to_h
        { id: @id, name: @name, arguments: @arguments }
      end

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
