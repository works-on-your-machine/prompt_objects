# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to list available primitives.
    # Shows stdlib primitives, custom (environment) primitives, and which ones
    # the current PO has active.
    class ListPrimitives < Primitives::Base
      # Names of stdlib primitives (built into the framework)
      STDLIB_PRIMITIVES = %w[read_file list_files write_file http_get].freeze

      description "List available primitives (deterministic Ruby tools). Filter by type: stdlib (built-in), custom (environment-specific), active (on this PO), or available (all)."
      param :filter, desc: "Filter primitives: 'available' (all), 'active' (currently on this PO), 'stdlib' (built-in), 'custom' (environment-specific). Default: 'available'"

      def execute(filter: "available")
        case filter.to_s
        when "stdlib"
          list_stdlib
        when "custom"
          list_custom
        when "active"
          list_active
        when "available"
          list_available
        else
          { error: "Unknown filter '#{filter}'. Use: available, active, stdlib, or custom." }
        end
      end

      private

      def list_stdlib
        primitives = STDLIB_PRIMITIVES.filter_map do |name|
          prim = registry.get(name)
          prim if ruby_llm_tool_class?(prim)
        end

        format_list("Stdlib Primitives (built-in)", primitives)
      end

      def list_custom
        primitives = registry.primitives.reject do |prim|
          name = extract_tool_name(prim)
          STDLIB_PRIMITIVES.include?(name) || universal_primitive?(prim)
        end

        if primitives.empty?
          "No custom primitives found.\nCustom primitives are stored in: #{environment&.primitives_dir}"
        else
          format_list("Custom Primitives (environment-specific)", primitives)
        end
      end

      def list_active
        caller = context&.calling_po
        unless caller
          return { error: "No calling PO context. This filter shows primitives active on the current PO." }
        end

        po = registry.get(caller)
        unless po.is_a?(PromptObject)
          return { error: "Could not find calling PO '#{caller}'." }
        end

        capabilities = po.config["capabilities"] || []
        active_primitives = capabilities.filter_map do |cap_name|
          cap = registry.get(cap_name)
          cap if ruby_llm_tool_class?(cap) && !universal_primitive?(cap)
        end

        if active_primitives.empty?
          "No primitives currently active on #{caller}.\nUse add_primitive to add primitives to your capabilities."
        else
          format_list("Active Primitives on #{caller}", active_primitives)
        end
      end

      def list_available
        # All registered primitives except universal ones
        primitives = registry.primitives.reject { |p| universal_primitive?(p) }

        # Categorize them
        stdlib = primitives.select { |p| STDLIB_PRIMITIVES.include?(extract_tool_name(p)) }
        custom = primitives.reject { |p| STDLIB_PRIMITIVES.include?(extract_tool_name(p)) }

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
        name = extract_tool_name(primitive)
        desc = primitive.respond_to?(:description) ? primitive.description : "No description"
        "- **#{name}**: #{desc}"
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
        # Universal capabilities live in PromptObjects::Universal module
        if primitive.is_a?(Class)
          primitive.name&.start_with?("PromptObjects::Universal")
        else
          primitive.class.name&.start_with?("PromptObjects::Universal")
        end
      end
    end
  end
end
