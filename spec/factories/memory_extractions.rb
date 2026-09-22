FactoryBot.define do
  factory :memory_extraction do
    generation_run
    personality { generation_run.conversation_thread.personality }
    status { :pending }
    attempts_count { 0 }
  end
end
