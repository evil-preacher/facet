# This file should ensure the existence of records required to run the application in every environment (production,
# development, test). The code here should be idempotent so that it can be executed at any point in every environment.
# The data can then be loaded with the bin/rails db:seed command (or created alongside the database with db:setup).
#
# Example:
#
prices = [
  {
    model: "gpt-4o",
    input_microusd_per_million: 2_500_000,
    cached_input_microusd_per_million: 1_250_000,
    output_microusd_per_million: 10_000_000
  },
  {
    model: "gpt-4o-2024-11-20",
    input_microusd_per_million: 2_500_000,
    cached_input_microusd_per_million: 1_250_000,
    output_microusd_per_million: 10_000_000
  },
  {
    model: "gpt-4o-mini",
    input_microusd_per_million: 150_000,
    cached_input_microusd_per_million: 75_000,
    output_microusd_per_million: 600_000
  }
]

prices.each do |attributes|
  ModelPrice.find_or_create_by!(
    provider: "openai",
    model: attributes.fetch(:model),
    effective_from: Time.utc(2026, 9, 19)
  ) do |price|
    price.assign_attributes(
      attributes.except(:model).merge(version: "openai-2026-09-19")
    )
  end
end
