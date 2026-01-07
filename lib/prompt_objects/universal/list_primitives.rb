# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to list available primitives.
    # Shows stdlib primitives, custom (environment) primitives, and which ones
    # the current PO has active.
    class ListPrimitives < Primitive
      # Names of stdlib primitives (built into the framework)
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      def name
        "list_primitives"
      end

      def description
        "List available primitives (deterministic Ruby tools). Filter by type: stdlib (built-in), custom (environment-specific), active (on this PO), or available (all)."
      end

      def parameters
        {
          type: "object",
          properties: {
            filter: {
              type: "string",
              enum: ["available", "active", "stdlib", "custom"],
              description: "Filter primitives: 'available' (all), 'active' (currently on this PO), 'stdlib' (built-in), 'custom' (environment-specific). Default: 'available'"
            }
          },
          required: []
        }
      end

      def receive(message, context:)
        filter = (message[:filter] || message["filter"] || "available").to_s

        case filter
        when "stdlib"
          list_stdlib(context)
        when "custom"
          list_custom(context)
        when "active"
          list_active(context)
        when "available"
          list_available(context)
        else
          "Error: Unknown filter '#{filter}'. Use: available, active, stdlib, or custom."
        end
      end

      private

      def list_stdlib(context)
        primitives = STDLIB_PRIMITIVES.filter_map do |name|
          prim = context.env.registry.get(name)
          prim if prim.is_a?(Primitive)
        end

        format_list("Stdlib Primitives (built-in)", primitives)
      end

      def list_custom(context)
        primitives = context.env.registry.primitives.reject do |prim|
          STDLIB_PRIMITIVES.include?(prim.name) || universal_primitive?(prim)
        end

        if primitives.empty?
          "No custom primitives found.\nCustom primitives are stored in: #{context.env.primitives_dir}"
        else
          format_list("Custom Primitives (environment-specific)", primitives)
        end
      end

      def list_active(context)
        caller = context.calling_po
        unless caller
          return "Error: No calling PO context. This filter shows primitives active on the current PO."
        end

        po = context.env.registry.get(caller)
        unless po.is_a?(PromptObject)
          return "Error: Could not find calling PO '#{caller}'."
        end

        capabilities = po.config["capabilities"] || []
        active_primitives = capabilities.filter_map do |cap_name|
          cap = context.env.registry.get(cap_name)
          cap if cap.is_a?(Primitive) && !universal_primitive?(cap)
        end

        if active_primitives.empty?
          "No primitives currently active on #{caller}.\nUse add_primitive to add primitives to your capabilities."
        else
          format_list("Active Primitives on #{caller}", active_primitives)
        end
      end

      def list_available(context)
        # All registered primitives except universal ones
        primitives = context.env.registry.primitives.reject { |p| universal_primitive?(p) }

        # Categorize them
        stdlib = primitives.select { |p| STDLIB_PRIMITIVES.include?(p.name) }
        custom = primitives.reject { |p| STDLIB_PRIMITIVES.include?(p.name) }

        lines = []

        unless stdlib.empty?
          lines << "## Stdlib Primitives (built-in)"
          stdlib.each { |p| lines << format_primitive(p) }
          lines << ""
        end

        unless custom.empty?
          lines << "## Custom Primitives (environment-specific)"
          custom.each { |p| lines << format_primitive(p) }
          lines << ""
        end

        if lines.empty?
          "No primitives available."
        else
          lines.join("\n")
        end
      end

      def format_list(title, primitives)
        return "#{title}: (none)" if primitives.empty?

        lines = ["## #{title}", ""]
        primitives.each { |p| lines << format_primitive(p) }
        lines.join("\n")
      end

      def format_primitive(primitive)
        "- **#{primitive.name}**: #{primitive.description}"
      end

      def universal_primitive?(primitive)
        # Universal capabilities live in PromptObjects::Universal module
        primitive.class.name&.start_with?("PromptObjects::Universal")
      end
    end
  end
end
