# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to store shared data scoped to the current delegation chain.
    # Any PO in the same delegation tree can read this data via get_env_data or list_env_data.
    class StoreEnvData < Primitive
      def name
        "store_env_data"
      end

      def description
        "Store a key-value pair in the shared environment data for this delegation chain. " \
        "All POs in the same delegation tree can access this data. " \
        "If the key already exists, it will be overwritten."
      end

      def parameters
        {
          type: "object",
          properties: {
            key: {
              type: "string",
              description: "Namespaced identifier for the data (e.g. 'arc_task', 'findings')"
            },
            short_description: {
              type: "string",
              description: "1-2 sentence summary of what this data contains (for discoverability via list_env_data)"
            },
            value: {
              description: "The data to store (any JSON-serializable value: string, number, object, array)"
            }
          },
          required: %w[key short_description value]
        }
      end

      def receive(message, context:)
        key = message[:key] || message["key"]
        short_description = message[:short_description] || message["short_description"]
        value = message[:value] || message["value"]

        return "Error: 'key' is required" unless key
        return "Error: 'short_description' is required" unless short_description
        return "Error: 'value' is required" if value.nil?

        root_thread_id = resolve_root_thread(context)
        return "Error: Could not resolve thread scope (no active session)" unless root_thread_id

        store = context.env.session_store
        return "Error: Session store not available" unless store

        stored_by = context.calling_po || "unknown"

        store.store_env_data(
          root_thread_id: root_thread_id,
          key: key,
          short_description: short_description,
          value: value,
          stored_by: stored_by
        )

        context.bus.publish(
          from: stored_by,
          to: "env_data",
          message: { action: "store", key: key, short_description: short_description }
        )

        context.env.notify_env_data_changed(action: "store", root_thread_id: root_thread_id, key: key, stored_by: stored_by)

        "Stored '#{key}' in environment data."
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
