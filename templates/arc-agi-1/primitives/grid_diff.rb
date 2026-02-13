# frozen_string_literal: true

module PromptObjects
  module Primitives
    class GridDiff < Primitive
      def name
        "grid_diff"
      end

      def description
        "Compare two ARC grids cell by cell. Shows which cells differ with coordinates and values."
      end

      def parameters
        {
          type: "object",
          properties: {
            grid_a: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "First grid (2D array)" },
            grid_b: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "Second grid (2D array)" }
          },
          required: ["grid_a", "grid_b"]
        }
      end

      def receive(message, context:)
        a = message[:grid_a] || message["grid_a"]
        b = message[:grid_b] || message["grid_b"]

        return "Error: grid_a and grid_b are required" unless a.is_a?(Array) && b.is_a?(Array)

        rows_a, cols_a = a.length, a[0]&.length || 0
        rows_b, cols_b = b.length, b[0]&.length || 0

        lines = []

        if rows_a != rows_b || cols_a != cols_b
          lines << "DIMENSION MISMATCH: #{rows_a}x#{cols_a} vs #{rows_b}x#{cols_b}"
          lines << ""
        end

        diffs = []
        matching = 0
        compare_rows = [rows_a, rows_b].min
        compare_cols = [cols_a, cols_b].min

        compare_rows.times do |r|
          compare_cols.times do |c|
            if a[r][c] == b[r][c]
              matching += 1
            else
              diffs << "(#{r},#{c}): #{a[r][c]} -> #{b[r][c]}"
            end
          end
        end

        total = compare_rows * compare_cols
        lines << "#{matching}/#{total} cells match (#{diffs.length} differ)"

        if diffs.empty? && rows_a == rows_b && cols_a == cols_b
          lines << "IDENTICAL"
        else
          diffs.first(30).each { |d| lines << "  #{d}" }
          lines << "  ... and #{diffs.length - 30} more" if diffs.length > 30
        end

        lines.join("\n")
      end
    end
  end
end
