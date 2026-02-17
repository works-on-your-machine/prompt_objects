# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to list all shared environment data keys and descriptions.
    # Returns a lightweight manifest without loading full values.
    class ListEnvData < Primitive
      def name
        "list_env_data"
      end

      def description
        "List all keys and descriptions in the shared environment data for this delegation chain. " \
        "Returns keys and short descriptions only (no values). " \
        "Use get_env_data to retrieve a specific key's full value."
      end

      def parameters
        {
          type: "object",
          properties: {},
          required: []
        }
      end

      def receive(message, context:)
        root_thread_id = resolve_root_thread(context)
        return "Error: Could not resolve thread scope (no active session)" unless root_thread_id

        store = context.env.session_store
        return "Error: Session store not available" unless store

        entries = store.list_env_data(root_thread_id: root_thread_id)

        if entries.empty?
          return "No environment data stored for this delegation chain."
        end

        context.bus.publish(
          from: context.calling_po || "unknown",
          to: "env_data",
          message: { action: "list", count: entries.size }
        )

        JSON.generate(entries)
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
