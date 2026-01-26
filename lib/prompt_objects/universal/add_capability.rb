# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to add capabilities to a prompt object at runtime.
    # This allows dynamic extension of POs after primitives are created.
    class AddCapability < Primitives::Base
      description "Add a capability to a prompt object, allowing it to use new tools. Can target self or another PO."
      param :target, desc: "Name of the prompt object to add the capability to. Use 'self' for the current PO."
      param :capability, desc: "Name of the capability to add (must already exist in the registry)"

      def execute(target:, capability:)
        # Resolve 'self' to the calling PO (not current_capability which is this tool)
        target = context&.calling_po if target == "self"

        # Find the target PO
        target_po = registry.get(target)
        unless target_po
          return { error: "Prompt object '#{target}' not found" }
        end

        unless target_po.is_a?(PromptObject)
          return { error: "'#{target}' is not a prompt object (can only add capabilities to POs)" }
        end

        # Check if capability exists
        unless registry.exists?(capability)
          return { error: "Capability '#{capability}' does not exist" }
        end

        # Check if already has it
        current_caps = target_po.config["capabilities"] || []
        if current_caps.include?(capability)
          return "'#{target}' already has the '#{capability}' capability"
        end

        # Add the capability
        target_po.config["capabilities"] ||= []
        target_po.config["capabilities"] << capability

        # Persist to file so it's available on restart
        saved = target_po.save

        # Notify for real-time UI update (don't wait for file watcher)
        environment&.notify_po_modified(target_po)

        if saved
          "Added '#{capability}' to '#{target}' and saved to file. It can now use this capability."
        else
          "Added '#{capability}' to '#{target}' (in-memory only, could not save to file). It can now use this capability."
        end
      end
    end
  end
end
