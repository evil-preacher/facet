FactoryBot.define do
  factory :model_price do
    provider { "openai" }
    model { "gpt-4o" }
    sequence(:version) { |number| "test-v#{number}" }
    input_microusd_per_million { 2_500_000 }
    cached_input_microusd_per_million { 1_250_000 }
    output_microusd_per_million { 10_000_000 }
    effective_from { Time.zone.parse("2026-01-01") }
    effective_until { nil }
  end
end
