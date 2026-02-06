# frozen_string_literal: true

module PromptObjects
  module Primitives
    class GridTransform < Primitive
      def name
        "grid_transform"
      end

      def description
        "Apply geometric transforms to a grid: rotate_90, rotate_180, rotate_270, flip_h, flip_v, transpose."
      end

      def parameters
        {
          type: "object",
          properties: {
            grid: { type: "array", description: "2D array of integers" },
            operation: {
              type: "string",
              enum: %w[rotate_90 rotate_180 rotate_270 flip_h flip_v transpose],
              description: "Transformation to apply"
            }
          },
          required: ["grid", "operation"]
        }
      end

      def receive(message, context:)
        grid = message[:grid] || message["grid"]
        op = message[:operation] || message["operation"]

        return "Error: grid is required" unless grid.is_a?(Array)
        return "Error: operation is required" unless op

        result = case op
                 when "rotate_90"  then grid.transpose.map(&:reverse)
                 when "rotate_180" then grid.reverse.map(&:reverse)
                 when "rotate_270" then grid.transpose.reverse
                 when "flip_h"     then grid.map(&:reverse)
                 when "flip_v"     then grid.reverse
                 when "transpose"  then grid.transpose
                 else return "Error: Unknown operation '#{op}'"
                 end

        JSON.generate(result)
      end
    end
  end
end
