FactoryBot.define do
  factory :relationship_state do
    personality { association :personality, :active }
    summary { "They have an established, friendly rapport." }
    revision { 1 }
  end
end
