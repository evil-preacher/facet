FactoryBot.define do
  factory :user do
    sequence(:email) { |number| "#{FFaker::Internet.user_name}#{number}@example.test" }

    trait :confirmed do
      confirmed_at { Time.current }
    end
  end
end
