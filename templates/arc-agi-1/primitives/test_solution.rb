# frozen_string_literal: true

module PromptObjects
  module Primitives
    class TestSolution < Primitive
      def name
        "test_solution"
      end

      def description
        "Test a solution against ARC training pairs. Provide either a primitive_name to run, or a grid to compare directly against the first training pair's expected output."
      end

      def parameters
        {
          type: "object",
          properties: {
            primitive_name: {
              type: "string",
              description: "Name of a primitive that accepts {grid: [[...]]} and returns a transformed grid"
            },
            grid: {
              type: "array",
              items: { type: "array", items: { type: "integer" } },
              description: "A grid to compare directly against expected output (for quick checks)"
            },
            expected: {
              type: "array",
              items: { type: "array", items: { type: "integer" } },
              description: "Expected output grid (used with 'grid' parameter)"
            },
            train: {
              type: "array",
              items: { type: "object" },
              description: "Training pairs array (used with 'primitive_name'). Each element has 'input' and 'output' grids."
            }
          },
          required: []
        }
      end

      def receive(message, context:)
        prim_name = message[:primitive_name] || message["primitive_name"]
        direct_grid = message[:grid] || message["grid"]

        if direct_grid
          return test_direct(direct_grid, message, context)
        elsif prim_name
          return test_primitive(prim_name, message, context)
        else
          return "Error: Provide either 'primitive_name' with 'train', or 'grid' with 'expected'"
        end
      end

      private

      def test_direct(actual, message, _context)
        expected = message[:expected] || message["expected"]
        return "Error: 'expected' grid is required for direct comparison" unless expected

        if actual == expected
          "PASS: Grid matches expected output exactly."
        else
          diff = compute_diff(actual, expected)
          "FAIL: #{diff}"
        end
      end

      def test_primitive(prim_name, message, context)
        train = message[:train] || message["train"]
        return "Error: 'train' array is required with primitive_name" unless train

        primitive = context.env.registry.get(prim_name)
        return "Error: Primitive '#{prim_name}' not found" unless primitive

        results = []
        passed = 0

        train.each_with_index do |pair, i|
          input = pair["input"] || pair[:input]
          expected = pair["output"] || pair[:output]

          begin
            actual = primitive.receive({ grid: input }, context: context)
            actual = JSON.parse(actual) if actual.is_a?(String)

            if actual == expected
              passed += 1
              results << "Pair #{i}: PASS"
            else
              diff = compute_diff(actual, expected)
              results << "Pair #{i}: FAIL - #{diff}"
            end
          rescue => e
            results << "Pair #{i}: ERROR - #{e.message}"
          end
        end

        "#{passed}/#{train.length} passed\n" + results.join("\n")
      end

      def compute_diff(actual, expected)
        unless actual.is_a?(Array)
          return "Output is not a grid (got #{actual.class})"
        end

        actual_rows = actual.length
        actual_cols = actual[0]&.length || 0
        exp_rows = expected.length
        exp_cols = expected[0]&.length || 0

        if actual_rows != exp_rows || actual_cols != exp_cols
          return "Dimension mismatch: expected #{exp_rows}x#{exp_cols}, got #{actual_rows}x#{actual_cols}"
        end

        wrong = 0
        details = []
        exp_rows.times do |r|
          exp_cols.times do |c|
            if actual[r][c] != expected[r][c]
              wrong += 1
              details << "(#{r},#{c}): expected #{expected[r][c]}, got #{actual[r][c]}" if details.length < 10
            end
          end
        end

        msg = "#{wrong} cells wrong"
        msg += "\n  " + details.join("\n  ") unless details.empty?
        msg += "\n  ... and #{wrong - 10} more" if wrong > 10
        msg
      end
    end
  end
end
