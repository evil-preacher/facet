FactoryBot.define do
  factory :generation_run do
    conversation_thread
    personality_version { conversation_thread.personality.current_version }
    user_message { association :message, conversation_thread: conversation_thread }
    assistant_message { nil }
    idempotency_key { SecureRandom.uuid }
    status { :pending }
    attempts_count { 0 }
  end
end
