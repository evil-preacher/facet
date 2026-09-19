require "rails_helper"

RSpec.describe Ai::CostCalculator do
  it "charges uncached input, cached input, and output with integer ceiling" do
    price = build(
      :model_price,
      input_microusd_per_million: 2_500_000,
      cached_input_microusd_per_million: 1_250_000,
      output_microusd_per_million: 10_000_000
    )

    cost = described_class.call(
      price: price,
      input_tokens: 1_001,
      cached_input_tokens: 400,
      output_tokens: 250
    )

    expect(cost).to eq(4_503)
  end

  it "rejects cached input greater than total input" do
    expect do
      described_class.call(
        price: build(:model_price),
        input_tokens: 2,
        cached_input_tokens: 3,
        output_tokens: 1
      )
    end.to raise_error(ArgumentError)
  end
end
