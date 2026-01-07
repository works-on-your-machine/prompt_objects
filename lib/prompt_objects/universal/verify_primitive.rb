# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to test primitives with sample inputs.
    # Helps POs verify their primitives work correctly before relying on them.
    class VerifyPrimitive < Primitive
      def name
        "verify_primitive"
      end

      def description
        "Test a primitive with sample inputs to verify it works correctly. Useful after creating or modifying a primitive."
      end

      def parameters
        {
          type: "object",
          properties: {
            name: {
              type: "string",
              description: "Name of the primitive to test"
            },
            tests: {
              type: "array",
              description: "Array of test cases. Each test has 'input' (Hash of parameters), and optionally 'expected' (exact match) or 'expected_error' (true if expecting an error)",
              items: {
                type: "object",
                properties: {
                  input: {
                    type: "object",
                    description: "Input parameters to pass to the primitive"
                  },
                  expected: {
                    description: "Expected output (for exact match)"
                  },
                  expected_error: {
                    type: "boolean",
                    description: "Set to true if this test should produce an error"
                  },
                  expected_contains: {
                    type: "string",
                    description: "String that should be contained in the output"
                  }
                }
              }
            }
          },
          required: ["name", "tests"]
        }
      end

      def receive(message, context:)
        prim_name = message[:name] || message["name"]
        tests = message[:tests] || message["tests"] || []

        # Find the primitive
        primitive = context.env.registry.get(prim_name)
        unless primitive
          return "Error: Primitive '#{prim_name}' not found."
        end

        unless primitive.is_a?(Primitive)
          return "Error: '#{prim_name}' is not a primitive."
        end

        if tests.empty?
          return "Error: No test cases provided. Include at least one test with 'input' parameters."
        end

        # Run tests
        results = tests.map.with_index { |test, i| run_test(primitive, test, i, context) }

        # Summarize
        passed = results.count { |r| r[:passed] }
        failed = results.count { |r| !r[:passed] }

        format_results(prim_name, passed, failed, results)
      end

      private

      def run_test(primitive, test, index, context)
        input = normalize_hash(test[:input] || test["input"] || {})
        expected = test[:expected] || test["expected"]
        expected_error = test[:expected_error] || test["expected_error"]
        expected_contains = test[:expected_contains] || test["expected_contains"]

        result = {
          test_num: index + 1,
          input: input,
          passed: false
        }

        begin
          output = primitive.receive(input, context: context)
          result[:output] = output

          if expected_error
            # Expected an error but got success
            result[:error_message] = "Expected an error but got: #{truncate(output.to_s, 100)}"
          elsif expected
            # Check exact match
            if output == expected
              result[:passed] = true
            else
              result[:error_message] = "Expected: #{truncate(expected.inspect, 100)}, Got: #{truncate(output.inspect, 100)}"
            end
          elsif expected_contains
            # Check if output contains expected string
            if output.to_s.include?(expected_contains)
              result[:passed] = true
            else
              result[:error_message] = "Expected output to contain '#{expected_contains}'"
            end
          else
            # No expectation, just check it didn't raise
            result[:passed] = true
          end
        rescue StandardError => e
          result[:error] = e.message

          if expected_error
            result[:passed] = true
          else
            result[:error_message] = "Unexpected error: #{e.message}"
          end
        end

        result
      end

      def normalize_hash(hash)
        return {} unless hash.is_a?(Hash)

        hash.transform_keys { |k| k.is_a?(String) ? k.to_sym : k }
      end

      def format_results(prim_name, passed, failed, results)
        lines = []
        lines << "## Verification Results for '#{prim_name}'"
        lines << ""

        status = failed.zero? ? "✓ All tests passed" : "✗ #{failed} test(s) failed"
        lines << "**Status**: #{status} (#{passed}/#{results.length})"
        lines << ""

        lines << "### Test Details"
        results.each do |r|
          icon = r[:passed] ? "✓" : "✗"
          lines << "#{icon} Test #{r[:test_num]}: input=#{r[:input].inspect}"

          if r[:passed]
            if r[:output]
              lines << "  Output: #{truncate(r[:output].to_s, 80)}"
            end
          else
            lines << "  **FAILED**: #{r[:error_message] || r[:error]}"
            if r[:output]
              lines << "  Actual output: #{truncate(r[:output].to_s, 80)}"
            end
          end
        end

        lines.join("\n")
      end

      def truncate(str, max_length)
        str.length > max_length ? "#{str[0, max_length]}..." : str
      end
    end
  end
end
