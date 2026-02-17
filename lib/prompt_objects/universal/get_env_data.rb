# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to retrieve shared data by key from the current delegation chain.
    class GetEnvData < Primitive
      def name
        "get_env_data"
      end

      def description
        "Retrieve a specific key's full value from the shared environment data. " \
        "Use list_env_data first to see what keys are available."
      end

      def parameters
        {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "The key to retrieve"
            }
          },
          required: ["key"]
        }
      end

      def receive(message, context:)
        key = message[:key] || message["key"]
        return "Error: 'key' is required" unless key

        root_thread_id = resolve_root_thread(context)
        return "Error: Could not resolve thread scope (no active session)" unless root_thread_id

        store = context.env.session_store
        return "Error: Session store not available" unless store

        entry = store.get_env_data(root_thread_id: root_thread_id, key: key)
        return "Key '#{key}' not found in environment data." unless entry

        context.bus.publish(
          from: context.calling_po || "unknown",
          to: "env_data",
          message: { action: "get", key: key }
        )

        JSON.generate(entry[:value])
      end

      private

      def resolve_root_thread(context)
        store = context.env.session_store
        return nil unless store

        po = context.env.registry.get(context.calling_po)
        return nil unless po&.respond_to?(:session_id) && po.session_id

        store.resolve_root_thread(po.session_id)
      end
    end
  end
end
