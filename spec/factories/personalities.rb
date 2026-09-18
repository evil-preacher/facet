FactoryBot.define do
  factory :personality do
    user
    sequence(:name) { |number| "Personality #{number}" }
    description { FFaker::Lorem.sentence }
    status { :draft }

    trait :active do
      after(:create) do |personality|
        version = create(:personality_version, personality: personality, number: 1)
        personality.update!(current_version: version, status: :active)
      end
    end
  end
end
