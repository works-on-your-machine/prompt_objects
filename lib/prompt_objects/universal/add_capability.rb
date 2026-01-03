# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to add capabilities to a prompt object at runtime.
    # This allows dynamic extension of POs after primitives are created.
    class AddCapability < Primitive
      def name
        "add_capability"
      end

      def description
        "Add a capability to a prompt object, allowing it to use new tools. Can target self or another PO."
      end

      def parameters
        {
          type: "object",
          properties: {
            target: {
              type: "string",
              description: "Name of the prompt object to add the capability to. Use 'self' for the current PO."
            },
            capability: {
              type: "string",
              description: "Name of the capability to add (must already exist in the registry)"
            }
          },
          required: ["target", "capability"]
        }
      end

      def receive(message, context:)
        target = message[:target] || message["target"]
        capability = message[:capability] || message["capability"]

        # Resolve 'self' to current capability
        target = context.current_capability if target == "self"

        # Find the target PO
        target_po = context.env.registry.get(target)
        unless target_po
          return "Error: Prompt object '#{target}' not found"
        end

        unless target_po.is_a?(PromptObject)
          return "Error: '#{target}' is not a prompt object (can only add capabilities to POs)"
        end

        # Check if capability exists
        unless context.env.registry.exists?(capability)
          return "Error: Capability '#{capability}' does not exist"
        end

        # Check if already has it
        current_caps = target_po.config["capabilities"] || []
        if current_caps.include?(capability)
          return "'#{target}' already has the '#{capability}' capability"
        end

        # Add the capability
        target_po.config["capabilities"] ||= []
        target_po.config["capabilities"] << capability

        "Added '#{capability}' to '#{target}'. It can now use this capability."
      end
    end
  end
end
