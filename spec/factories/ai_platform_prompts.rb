FactoryBot.define do
  factory :ai_platform_prompt do
    provider { "mistral" }
    purpose { "conversation" }
    sequence(:revision)
    content { "Provider-specific correction for the conversation." }
    status { "active" }
    published_at { Time.current }
  end
end
