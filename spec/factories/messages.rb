FactoryBot.define do
  factory :message do
    conversation_thread
    personality_version { conversation_thread.personality.current_version }
    position { conversation_thread.messages.maximum(:position).to_i + 1 }
    role { :user }
    status { :completed }
    language { Ai::LanguageDetector.call(content) }
    content { FFaker::Lorem.sentence }
    client_token { SecureRandom.uuid }

    trait :assistant do
      role { :assistant }
      client_token { nil }
    end
  end
end
