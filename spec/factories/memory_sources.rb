FactoryBot.define do
  factory :memory_source do
    memory
    message do
      thread = association(:conversation_thread, personality: memory.personality)
      association :message,
                  conversation_thread: thread,
                  personality_version: memory.personality.current_version
    end
  end
end
