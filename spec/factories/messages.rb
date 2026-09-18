FactoryBot.define do
  factory :message do
    conversation_thread
    personality_version { conversation_thread.personality.current_version }
    position { conversation_thread.messages.maximum(:position).to_i + 1 }
    role { :user }
    status { :completed }
    content { FFaker::Lorem.sentence }
    client_token { SecureRandom.uuid }
  end
end
