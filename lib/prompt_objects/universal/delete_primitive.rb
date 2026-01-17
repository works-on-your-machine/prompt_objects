# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to delete a primitive file from the environment.
    # This is for recovery when a broken primitive is causing problems.
    # USE WITH CAUTION - this permanently deletes the primitive file.
    class DeletePrimitive < Primitive
      # Built-in primitives that cannot be deleted
      PROTECTED_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      def name
        "delete_primitive"
      end

      def description
        "Delete a primitive (Ruby tool) file from the environment. This is a DESTRUCTIVE operation - use for recovery when a broken primitive is causing problems. Cannot delete built-in primitives."
      end

      def parameters
        {
          type: "object",
          properties: {
            primitive: {
              type: "string",
              description: "Name of the primitive to delete"
            },
            confirm: {
              type: "boolean",
              description: "Must be true to confirm deletion. This is a safety check."
            }
          },
          required: ["primitive", "confirm"]
        }
      end

      def receive(message, context:)
        primitive_name = message[:primitive] || message["primitive"]
        confirm = message[:confirm] || message["confirm"]

        # Safety check
        unless confirm == true
          return "Error: Must set confirm=true to delete a primitive. This is a destructive operation."
        end

        # Check if it's a protected primitive
        if PROTECTED_PRIMITIVES.include?(primitive_name)
          return "Error: Cannot delete built-in primitive '#{primitive_name}'."
        end

        # Check if it's a universal capability
        if UNIVERSAL_CAPABILITIES.include?(primitive_name)
          return "Error: Cannot delete universal capability '#{primitive_name}'."
        end

        # Find the primitive file
        primitives_dir = context.env.primitives_dir
        path = File.join(primitives_dir, "#{primitive_name}.rb")

        unless File.exist?(path)
          return "Error: Primitive file not found at #{path}. It may be a built-in primitive or not exist."
        end

        # Unregister from registry first
        context.env.registry.unregister(primitive_name)

        # Delete the file
        begin
          File.delete(path)
          "Deleted primitive '#{primitive_name}' and removed from registry. File: #{path}"
        rescue => e
          "Error deleting file: #{e.message}. Primitive was unregistered from memory."
        end
      end
    end
  end
end
