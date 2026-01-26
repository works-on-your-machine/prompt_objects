# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to delete a primitive file from the environment.
    # This is for recovery when a broken primitive is causing problems.
    # USE WITH CAUTION - this permanently deletes the primitive file.
    class DeletePrimitive < Primitives::Base
      # Built-in primitives that cannot be deleted
      PROTECTED_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      description "Delete a primitive (Ruby tool) file from the environment. This is a DESTRUCTIVE operation - use for recovery when a broken primitive is causing problems. Cannot delete built-in primitives."
      param :primitive, desc: "Name of the primitive to delete"
      param :confirm, desc: "Must be 'true' to confirm deletion. This is a safety check."

      def execute(primitive:, confirm:)
        # Safety check
        unless confirm.to_s == "true"
          return { error: "Must set confirm='true' to delete a primitive. This is a destructive operation." }
        end

        # Check if it's a protected primitive
        if PROTECTED_PRIMITIVES.include?(primitive)
          return { error: "Cannot delete built-in primitive '#{primitive}'." }
        end

        # Check if it's a universal capability
        if UNIVERSAL_CAPABILITIES.include?(primitive)
          return { error: "Cannot delete universal capability '#{primitive}'." }
        end

        # Find the primitive file
        primitives_dir = environment.primitives_dir
        path = File.join(primitives_dir, "#{primitive}.rb")

        unless File.exist?(path)
          return { error: "Primitive file not found at #{path}. It may be a built-in primitive or not exist." }
        end

        # Unregister from registry first
        registry.unregister(primitive)

        # Delete the file
        begin
          File.delete(path)
          "Deleted primitive '#{primitive}' and removed from registry. File: #{path}"
        rescue => e
          { error: "Error deleting file: #{e.message}. Primitive was unregistered from memory." }
        end
      end
    end
  end
end
