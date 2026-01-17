# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to add primitives to the current PO.
    # Focused version of add_capability specifically for primitives with better UX.
    class AddPrimitive < Primitive
      # Names of stdlib primitives (built into the framework)
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      def name
        "add_primitive"
      end

      def description
        "Add a primitive (deterministic Ruby tool) to your capabilities. Use list_primitives first to see what's available."
      end

      def parameters
        {
          type: "object",
          properties: {
            primitive: {
              type: "string",
              description: "Name of the primitive to add (e.g., 'read_file', 'write_file')"
            }
          },
          required: ["primitive"]
        }
      end

      def receive(message, context:)
        primitive_name = message[:primitive] || message["primitive"]

        # Find the calling PO
        caller = context.calling_po
        unless caller
          return "Error: No calling PO context. This capability adds primitives to the current PO."
        end

        target_po = context.env.registry.get(caller)
        unless target_po.is_a?(PromptObject)
          return "Error: Could not find calling PO '#{caller}'."
        end

        # Check if primitive exists
        primitive = context.env.registry.get(primitive_name)
        unless primitive
          return suggest_primitives(primitive_name, context)
        end

        unless primitive.is_a?(Primitive)
          return "Error: '#{primitive_name}' is not a primitive (it's a prompt object). Use add_capability for POs."
        end

        # Check if it's a universal capability (shouldn't be added explicitly)
        if universal_primitive?(primitive)
          return "Error: '#{primitive_name}' is a universal capability and is already available to all POs."
        end

        # Check if already has it
        current_caps = target_po.config["capabilities"] || []
        if current_caps.include?(primitive_name)
          return "You already have the '#{primitive_name}' primitive."
        end

        # Add the primitive
        target_po.config["capabilities"] ||= []
        target_po.config["capabilities"] << primitive_name

        # Persist to file so it's available on restart
        saved = target_po.save

        # Notify for real-time UI update
        context.env.notify_po_modified(target_po)

        if saved
          "Added '#{primitive_name}' to your capabilities and saved to file. You can now use it."
        else
          "Added '#{primitive_name}' to your capabilities (in-memory only). You can now use it."
        end
      end

      private

      def suggest_primitives(name, context)
        # Get all available primitives (excluding universal ones)
        available = context.env.registry.primitives
          .reject { |p| universal_primitive?(p) }
          .map(&:name)

        # Find similar names
        suggestions = available.select { |n| n.include?(name) || name.include?(n) || levenshtein_similar?(n, name) }

        if suggestions.any?
          "Error: Primitive '#{name}' not found. Did you mean: #{suggestions.join(', ')}?"
        else
          "Error: Primitive '#{name}' not found. Available primitives: #{available.join(', ')}"
        end
      end

      def universal_primitive?(primitive)
        primitive.class.name&.start_with?("PromptObjects::Universal")
      end

      # Simple check for similar strings (within 2 edits)
      def levenshtein_similar?(a, b)
        return true if a == b
        return false if (a.length - b.length).abs > 2

        # Simple approximation: check if they share most characters
        common = (a.chars & b.chars).length
        max_len = [a.length, b.length].max
        common.to_f / max_len > 0.6
      end
    end
  end
end
