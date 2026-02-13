# frozen_string_literal: true

module PromptObjects
  # Base class for all capabilities (both primitives and prompt objects).
  # Everything in the system implements this interface.
  class Capability
    attr_reader :name, :description
    attr_accessor :state

    def initialize
      @state = :idle
    end

    # Handle a message and return a response.
    # @param message [String, Hash] The incoming message
    # @param context [Context] Execution context with environment reference
    # @return [String] The response
    def receive(message, context:)
      raise NotImplementedError, "#{self.class} must implement #receive"
    end

    # Generate a tool descriptor for LLM function calling.
    # @return [Hash] OpenAI-compatible tool descriptor
    def descriptor
      {
        type: "function",
        function: {
          name: name,
          description: description,
          parameters: sanitize_schema(parameters)
        }
      }
    end

    private

    # Ensure array-typed properties have an `items` field.
    # LLM APIs (Gemini, OpenAI, Ollama) reject array schemas without items.
    def sanitize_schema(schema)
      return schema unless schema.is_a?(Hash)

      schema = schema.dup

      if schema[:type] == "array" && !schema.key?(:items) && !schema.key?("items")
        schema[:items] = {}
      end

      if schema[:properties].is_a?(Hash)
        schema[:properties] = schema[:properties].transform_values { |v| sanitize_schema(v) }
      end

      schema
    end

    public

    # Define the parameters this capability accepts.
    # Override in subclasses for specific parameter schemas.
    # @return [Hash] JSON Schema for parameters
    def parameters
      {
        type: "object",
        properties: {},
        required: []
      }
    end
  end
end
