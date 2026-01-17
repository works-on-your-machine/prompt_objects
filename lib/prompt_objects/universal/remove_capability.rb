# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to remove capabilities from a prompt object.
    # Useful for cleanup or recovery when a capability is broken or no longer needed.
    class RemoveCapability < Primitive
      def name
        "remove_capability"
      end

      def description
        "Remove a capability from a prompt object. This removes it from the PO's declared capabilities but does NOT delete the underlying primitive/PO file. Use delete_primitive to fully remove a broken primitive."
      end

      def parameters
        {
          type: "object",
          properties: {
            target: {
              type: "string",
              description: "Name of the prompt object to remove the capability from. Use 'self' for the current PO."
            },
            capability: {
              type: "string",
              description: "Name of the capability to remove"
            }
          },
          required: ["target", "capability"]
        }
      end

      def receive(message, context:)
        target = message[:target] || message["target"]
        capability = message[:capability] || message["capability"]

        # Resolve 'self' to the calling PO
        target = context.calling_po if target == "self"

        # Find the target PO
        target_po = context.env.registry.get(target)
        unless target_po
          return "Error: Prompt object '#{target}' not found"
        end

        unless target_po.is_a?(PromptObject)
          return "Error: '#{target}' is not a prompt object"
        end

        # Check if the capability is declared
        current_caps = target_po.config["capabilities"] || []
        unless current_caps.include?(capability)
          return "'#{target}' does not have '#{capability}' in its declared capabilities."
        end

        # Remove the capability
        target_po.config["capabilities"].delete(capability)

        # Persist to file
        saved = target_po.save

        # Notify for real-time UI update
        context.env.notify_po_modified(target_po)

        if saved
          "Removed '#{capability}' from '#{target}' and saved to file."
        else
          "Removed '#{capability}' from '#{target}' (in-memory only, could not save to file)."
        end
      end
    end
  end
end
