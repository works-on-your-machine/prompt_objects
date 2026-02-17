# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to delete a key from the shared environment data.
    class DeleteEnvData < Primitive
      def name
        "delete_env_data"
      end

      def description
        "Delete a key from the shared environment data for this delegation chain."
      end

      def parameters
        {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "The key to delete"
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

        deleted = store.delete_env_data(root_thread_id: root_thread_id, key: key)

        unless deleted
          return "Key '#{key}' not found in environment data."
        end

        stored_by = context.calling_po || "unknown"

        context.bus.publish(
          from: stored_by,
          to: "env_data",
          message: { action: "delete", key: key }
        )

        context.env.notify_env_data_changed(action: "delete", root_thread_id: root_thread_id, key: key, stored_by: stored_by)

        "Deleted '#{key}' from environment data."
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
