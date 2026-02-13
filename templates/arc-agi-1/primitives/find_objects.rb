# frozen_string_literal: true

module PromptObjects
  module Primitives
    class FindObjects < Primitive
      def name
        "find_objects"
      end

      def description
        "Find connected objects (same-color adjacent cells) in a grid. Returns objects with color, cell count, and bounding box."
      end

      def parameters
        {
          type: "object",
          properties: {
            grid: { type: "array", items: { type: "array", items: { type: "integer" } }, description: "2D array of integers" },
            background: { type: "integer", description: "Background color to ignore (default: 0)" }
          },
          required: ["grid"]
        }
      end

      def receive(message, context:)
        grid = message[:grid] || message["grid"]
        bg = message[:background] || message["background"] || 0

        return "Error: grid is required" unless grid.is_a?(Array)
        return "Error: grid is empty" if grid.empty?

        rows = grid.length
        cols = grid[0]&.length || 0
        visited = Array.new(rows) { Array.new(cols, false) }
        objects = []

        rows.times do |r|
          cols.times do |c|
            next if visited[r][c] || grid[r][c] == bg

            color = grid[r][c]
            cells = []
            queue = [[r, c]]
            visited[r][c] = true

            while (pos = queue.shift)
              cr, cc = pos
              cells << [cr, cc]
              [[-1, 0], [1, 0], [0, -1], [0, 1]].each do |dr, dc|
                nr, nc = cr + dr, cc + dc
                next if nr < 0 || nr >= rows || nc < 0 || nc >= cols
                next if visited[nr][nc] || grid[nr][nc] != color
                visited[nr][nc] = true
                queue << [nr, nc]
              end
            end

            rs = cells.map(&:first)
            cs = cells.map(&:last)
            objects << {
              color: color,
              cells: cells.length,
              bounds: { top: rs.min, left: cs.min, bottom: rs.max, right: cs.max }
            }
          end
        end

        JSON.pretty_generate({ total_objects: objects.length, objects: objects })
      end
    end
  end
end
