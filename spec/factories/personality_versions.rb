FactoryBot.define do
  factory :personality_version do
    personality
    sequence(:number) { |number| number }
    content { "# Character\n\n#{FFaker::Lorem.paragraph}" }
  end
end
