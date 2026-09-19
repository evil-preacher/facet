FactoryBot.define do
  factory :model_call do
    user
    personality { nil }
    generation_run { nil }
    purpose { :conversation }
    provider { "mistral" }
    model { "mistral-large-2512" }
    status { :pending }
  end
end
