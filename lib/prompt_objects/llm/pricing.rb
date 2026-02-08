# frozen_string_literal: true

module PromptObjects
  module LLM
    # Static pricing table for cost estimation.
    # Prices are per 1 million tokens in USD.
    # Updated periodically — not guaranteed to be exact.
    class Pricing
      RATES = {
        # OpenAI
        "gpt-5.2" => { input: 2.00, output: 8.00 },
        "gpt-4.1" => { input: 2.00, output: 8.00 },
        "gpt-4.1-mini" => { input: 0.40, output: 1.60 },
        "gpt-4.5-preview" => { input: 75.00, output: 150.00 },
        "o3-mini" => { input: 1.10, output: 4.40 },
        "o1" => { input: 15.00, output: 60.00 },
        # Anthropic
        "claude-opus-4" => { input: 15.00, output: 75.00 },
        "claude-sonnet-4-5" => { input: 3.00, output: 15.00 },
        "claude-haiku-4-5" => { input: 1.00, output: 5.00 },
        # Gemini
        "gemini-3-flash-preview" => { input: 0.15, output: 0.60 },
        "gemini-2.5-pro" => { input: 1.25, output: 10.00 },
        "gemini-2.5-flash" => { input: 0.15, output: 0.60 },
      }.freeze

      # Calculate cost in USD for a given usage.
      # @param model [String] Model name
      # @param input_tokens [Integer] Number of input tokens
      # @param output_tokens [Integer] Number of output tokens
      # @return [Float] Estimated cost in USD
      def self.calculate(model:, input_tokens:, output_tokens:)
        rates = RATES[model]
        return 0.0 unless rates

        input_cost = (input_tokens / 1_000_000.0) * rates[:input]
        output_cost = (output_tokens / 1_000_000.0) * rates[:output]
        input_cost + output_cost
      end

      # Check if we have pricing data for a model.
      # @param model [String] Model name
      # @return [Boolean]
      def self.known_model?(model)
        RATES.key?(model)
      end
    end
  end
end
