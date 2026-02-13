# frozen_string_literal: true

module PromptObjects
  module Primitives
    class GridInfo < Primitive
      def name
        "grid_info"
      end

      def description
        "Get grid dimensions, color frequencies, and density."
      end

      def parameters
        {
          type: "object",
          properties: {
            grid: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "2D array of integers" }
          },
          required: ["grid"]
        }
      end

      def receive(message, context:)
        grid = message[:grid] || message["grid"]
        return "Error: grid is required" unless grid.is_a?(Array)
        return "Error: grid is empty" if grid.empty?

        flat = grid.flatten
        colors = flat.tally.sort.to_h

        JSON.pretty_generate({
          rows: grid.length,
          cols: grid[0]&.length || 0,
          total_cells: flat.length,
          colors: colors,
          non_background: flat.count { |c| c != 0 }
        })
      end
    end
  end
end
