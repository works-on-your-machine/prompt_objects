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
          parameters: parameters
        }
      }
    end

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
