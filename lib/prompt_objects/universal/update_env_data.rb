# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to update an existing shared environment data entry.
    # Fails if the key doesn't exist (use store_env_data for create-or-replace).
    class UpdateEnvData < Primitive
      def name
        "update_env_data"
      end

      def description
        "Update an existing key's value and/or description in the shared environment data. " \
        "Fails if the key doesn't exist — use store_env_data to create new entries."
      end

      def parameters
        {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "The key to update (must already exist)"
            },
            short_description: {
              type: "string",
              description: "New description (keeps existing if omitted)"
            },
            value: {
              description: "New value (keeps existing if omitted)"
            }
          },
          required: ["key"]
        }
      end

      def receive(message, context:)
        key = message[:key] || message["key"]
        short_description = message[:short_description] || message["short_description"]
        value = message[:value] || message["value"]

        return "Error: 'key' is required" unless key

        root_thread_id = resolve_root_thread(context)
        return "Error: Could not resolve thread scope (no active session)" unless root_thread_id

        store = context.env.session_store
        return "Error: Session store not available" unless store

        stored_by = context.calling_po || "unknown"

        updated = store.update_env_data(
          root_thread_id: root_thread_id,
          key: key,
          short_description: short_description,
          value: value,
          stored_by: stored_by
        )

        unless updated
          return "Key '#{key}' not found in environment data. Use store_env_data to create it."
        end

        context.bus.publish(
          from: stored_by,
          to: "env_data",
          message: { action: "update", key: key }
        )

        "Updated '#{key}' in environment data."
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
