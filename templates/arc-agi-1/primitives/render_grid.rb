# frozen_string_literal: true

module PromptObjects
  module Primitives
    class RenderGrid < Primitive
      SYMBOLS = {
        0 => ".", 1 => "1", 2 => "2", 3 => "3", 4 => "4",
        5 => "5", 6 => "6", 7 => "7", 8 => "8", 9 => "9"
      }.freeze

      COLOR_NAMES = {
        0 => "black", 1 => "blue", 2 => "red", 3 => "green", 4 => "yellow",
        5 => "grey", 6 => "magenta", 7 => "orange", 8 => "cyan", 9 => "maroon"
      }.freeze

      def name
        "render_grid"
      end

      def description
        "Render an ARC grid as readable text with coordinates. Background (0) shown as dots, colors 1-9 as digits."
      end

      def parameters
        {
          type: "object",
          properties: {
            grid: {
              type: "array",
              description: "2D array of integers 0-9"
            },
            label: {
              type: "string",
              description: "Optional label to display above the grid"
            }
          },
          required: ["grid"]
        }
      end

      def receive(message, context:)
        grid = message[:grid] || message["grid"]
        label = message[:label] || message["label"]

        return "Error: grid is required" unless grid.is_a?(Array)
        return "Error: grid is empty" if grid.empty?

        rows = grid.length
        cols = grid[0]&.length || 0
        lines = []

        lines << label if label
        lines << "#{rows}x#{cols}"

        # Column headers
        col_header = "   " + (0...cols).map { |c| c.to_s.rjust(2) }.join
        lines << col_header
        lines << "   " + "--" * cols

        # Rows with line numbers
        grid.each_with_index do |row, r|
          cells = row.map { |v| (SYMBOLS[v] || "?").rjust(2) }.join
          lines << "#{r.to_s.rjust(2)}|#{cells}"
        end

        # Color legend for non-background colors present
        present = grid.flatten.uniq.sort - [0]
        unless present.empty?
          legend = present.map { |c| "#{c}=#{COLOR_NAMES[c]}" }.join(", ")
          lines << ""
          lines << "Colors: #{legend}"
        end

        lines.join("\n")
      end
    end
  end
end
