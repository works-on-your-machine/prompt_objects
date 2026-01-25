# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to add primitives to the current PO.
    # Focused version of add_capability specifically for primitives with better UX.
    class AddPrimitive < Primitives::Base
      # Names of stdlib primitives (built into the framework)
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      description "Add a primitive (deterministic Ruby tool) to your capabilities. Use list_primitives first to see what's available."
      param :primitive, desc: "Name of the primitive to add (e.g., 'read_file', 'write_file')"

      def execute(primitive:)
        # Find the calling PO
        caller = context&.calling_po
        unless caller
          return { error: "No calling PO context. This capability adds primitives to the current PO." }
        end

        target_po = registry.get(caller)
        unless target_po.is_a?(PromptObject)
          return { error: "Could not find calling PO '#{caller}'." }
        end

        # Check if primitive exists
        prim = registry.get(primitive)
        unless prim
          return suggest_primitives(primitive)
        end

        unless ruby_llm_tool_class?(prim)
          return { error: "'#{primitive}' is not a primitive (it may be a prompt object). Use add_capability for POs." }
        end

        # Check if it's a universal capability (shouldn't be added explicitly)
        if universal_primitive?(prim)
          return { error: "'#{primitive}' is a universal capability and is already available to all POs." }
        end

        # Check if already has it
        current_caps = target_po.config["capabilities"] || []
        if current_caps.include?(primitive)
          return "You already have the '#{primitive}' primitive."
        end

        # Add the primitive
        target_po.config["capabilities"] ||= []
        target_po.config["capabilities"] << primitive

        # Persist to file so it's available on restart
        saved = target_po.save

        # Notify for real-time UI update
        environment&.notify_po_modified(target_po)

        if saved
          "Added '#{primitive}' to your capabilities and saved to file. You can now use it."
        else
          "Added '#{primitive}' to your capabilities (in-memory only). You can now use it."
        end
      end

      private

      def suggest_primitives(name)
        # Get all available primitives (excluding universal ones)
        available = registry.primitives
          .reject { |p| universal_primitive?(p) }
          .map { |p| extract_tool_name(p) }

        # Find similar names
        suggestions = available.select { |n| n.include?(name) || name.include?(n) || levenshtein_similar?(n, name) }

        if suggestions.any?
          { error: "Primitive '#{name}' not found. Did you mean: #{suggestions.join(', ')}?" }
        else
          { error: "Primitive '#{name}' not found. Available primitives: #{available.join(', ')}" }
        end
      end

      def extract_tool_name(prim)
        if prim.respond_to?(:tool_name)
          prim.tool_name
        elsif prim.is_a?(Class)
          prim.name.split("::").last.gsub(/([a-z])([A-Z])/, '\1_\2').downcase
        else
          prim.name
        end
      end

      def ruby_llm_tool_class?(cap)
        cap.is_a?(Class) && defined?(RubyLLM::Tool) && cap < RubyLLM::Tool
      end

      def universal_primitive?(primitive)
        if primitive.is_a?(Class)
          primitive.name&.start_with?("PromptObjects::Universal")
        else
          primitive.class.name&.start_with?("PromptObjects::Universal")
        end
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
