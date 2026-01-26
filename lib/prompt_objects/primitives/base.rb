# frozen_string_literal: true

require "ruby_llm"

module PromptObjects
  module Primitives
    # Base class for all primitives.
    # Inherits from RubyLLM::Tool so primitives are natively executable by RubyLLM.
    #
    # Context is injected at the class level before tool execution, allowing
    # primitives to access the environment, registry, and message bus.
    #
    # Example usage:
    #   class ReadFile < Primitives::Base
    #     description "Read the contents of a file"
    #     param :path, desc: "The path to the file"
    #
    #     def execute(path:)
    #       File.read(path)
    #     end
    #   end
    #
    class Base < RubyLLM::Tool
      class << self
        # Context is injected before tool execution
        attr_accessor :context

        # Keep track of tool name for registry lookup
        def tool_name
          @tool_name ||= name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        end

        # Allow overriding the tool name
        def set_name(new_name)
          @tool_name = new_name
        end
      end

      # Instance access to class-level context
      def context
        self.class.context
      end

      # Convenience accessors for context components
      def environment
        context&.env
      end

      def registry
        context&.env&.registry
      end

      def message_bus
        context&.bus
      end

      def human_queue
        context&.human_queue
      end

      def current_capability
        context&.current_capability
      end

      # Log a message to the message bus
      def log(message, to: nil)
        message_bus&.publish(
          from: self.class.tool_name,
          to: to,
          message: message
        )
      end
    end
  end
end
