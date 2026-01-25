# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to remove capabilities from a prompt object.
    # Useful for cleanup or recovery when a capability is broken or no longer needed.
    class RemoveCapability < Primitives::Base
      description "Remove a capability from a prompt object. This removes it from the PO's declared capabilities but does NOT delete the underlying primitive/PO file. Use delete_primitive to fully remove a broken primitive."
      param :target, desc: "Name of the prompt object to remove the capability from. Use 'self' for the current PO."
      param :capability, desc: "Name of the capability to remove"

      def execute(target:, capability:)
        # Resolve 'self' to the calling PO
        target = context&.calling_po if target == "self"

        # Find the target PO
        target_po = registry.get(target)
        unless target_po
          return { error: "Prompt object '#{target}' not found" }
        end

        unless target_po.is_a?(PromptObject)
          return { error: "'#{target}' is not a prompt object" }
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
        environment&.notify_po_modified(target_po)

        if saved
          "Removed '#{capability}' from '#{target}' and saved to file."
        else
          "Removed '#{capability}' from '#{target}' (in-memory only, could not save to file)."
        end
      end
    end
  end
end
