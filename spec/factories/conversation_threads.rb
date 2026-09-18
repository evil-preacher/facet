FactoryBot.define do
  factory :conversation_thread do
    association :personality, :active
    sequence(:title) { |number| "Conversation #{number}" }
    status { :active }
    last_message_at { nil }
  end
end
