FactoryBot.define do
  factory :personality do
    user
    sequence(:name) { |number| "Personality #{number}" }
    description { FFaker::Lorem.sentence }
    status { :draft }
  end
end
