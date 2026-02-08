# frozen_string_literal: true

require_relative "../../test_helper"

class PricingTest < PromptObjectsTest
  def test_calculate_known_model
    cost = PromptObjects::LLM::Pricing.calculate(
      model: "gpt-4.1",
      input_tokens: 1_000_000,
      output_tokens: 1_000_000
    )

    # gpt-4.1: $2/M input + $8/M output = $10
    assert_in_delta 10.0, cost, 0.001
  end

  def test_calculate_small_usage
    cost = PromptObjects::LLM::Pricing.calculate(
      model: "gpt-4.1-mini",
      input_tokens: 500,
      output_tokens: 100
    )

    # 500/1M * 0.40 + 100/1M * 1.60 = 0.0002 + 0.00016 = 0.00036
    assert_in_delta 0.00036, cost, 0.00001
  end

  def test_calculate_unknown_model_returns_zero
    cost = PromptObjects::LLM::Pricing.calculate(
      model: "unknown-model",
      input_tokens: 1000,
      output_tokens: 1000
    )

    assert_equal 0.0, cost
  end

  def test_calculate_zero_tokens
    cost = PromptObjects::LLM::Pricing.calculate(
      model: "gpt-4.1",
      input_tokens: 0,
      output_tokens: 0
    )

    assert_equal 0.0, cost
  end

  def test_known_model_true
    assert PromptObjects::LLM::Pricing.known_model?("claude-sonnet-4-5")
  end

  def test_known_model_false
    refute PromptObjects::LLM::Pricing.known_model?("some-random-model")
  end

  def test_all_rates_have_input_and_output
    PromptObjects::LLM::Pricing::RATES.each do |model, rates|
      assert rates[:input], "#{model} missing :input rate"
      assert rates[:output], "#{model} missing :output rate"
      assert rates[:input] >= 0, "#{model} has negative input rate"
      assert rates[:output] >= 0, "#{model} has negative output rate"
    end
  end
end
