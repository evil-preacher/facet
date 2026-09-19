FactoryBot.define do
  factory :model_call do
    user
    personality { nil }
    generation_run { nil }
    purpose { :conversation }
    provider { "openai" }
    model { "gpt-4o" }
    status { :pending }
  end
end
