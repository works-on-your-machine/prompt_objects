# frozen_string_literal: true

module PromptObjects
  module Universal
    # Universal capability to test primitives with sample inputs.
    # Helps POs verify their primitives work correctly before relying on them.
    class VerifyPrimitive < Primitives::Base
      description "Test a primitive with sample inputs to verify it works correctly. Useful after creating or modifying a primitive."
      param :name, desc: "Name of the primitive to test"
      param :tests, desc: "JSON array of test cases. Each test has 'input' (object of parameters), and optionally 'expected' (exact match), 'expected_error' (true if expecting error), or 'expected_contains' (string to find in output)"

      def execute(name:, tests:)
        # Parse tests if string
        tests_array = tests.is_a?(String) ? (JSON.parse(tests) rescue []) : tests

        # Find the primitive
        primitive = registry.get(name)
        unless primitive
          return { error: "Primitive '#{name}' not found." }
        end

        unless ruby_llm_tool_class?(primitive)
          return { error: "'#{name}' is not a primitive." }
        end

        if tests_array.empty?
          return { error: "No test cases provided. Include at least one test with 'input' parameters." }
        end

        # Run tests
        results = tests_array.map.with_index { |test, i| run_test(primitive, test, i) }

        # Summarize
        passed = results.count { |r| r[:passed] }
        failed = results.count { |r| !r[:passed] }

        format_results(name, passed, failed, results)
      end

      private

      def ruby_llm_tool_class?(cap)
        cap.is_a?(Class) && defined?(RubyLLM::Tool) && cap < RubyLLM::Tool
      end

      def run_test(primitive_class, test, index)
        input = normalize_hash(test["input"] || test[:input] || {})
        expected = test["expected"] || test[:expected]
        expected_error = test["expected_error"] || test[:expected_error]
        expected_contains = test["expected_contains"] || test[:expected_contains]

        result = {
          test_num: index + 1,
          input: input,
          passed: false
        }

        begin
          # Create instance and execute
          instance = primitive_class.new
          output = instance.execute(**input)
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

        status = failed.zero? ? "All tests passed" : "#{failed} test(s) failed"
        lines << "**Status**: #{status} (#{passed}/#{results.length})"
        lines << ""

        lines << "### Test Details"
        results.each do |r|
          icon = r[:passed] ? "PASS" : "FAIL"
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
