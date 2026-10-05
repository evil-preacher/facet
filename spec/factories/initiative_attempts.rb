FactoryBot.define do
  factory :initiative_attempt do
    association :personality, :active
    conversation_thread { create(:conversation_thread, personality: personality) }
    personality_version { personality.current_version }
    source_message { create(:message, conversation_thread: conversation_thread, created_at: 2.days.ago) }
    ai_provider { "mistral" }
    status { :pending }
  end
end
