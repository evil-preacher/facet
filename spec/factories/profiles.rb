FactoryBot.define do
  factory :profile do
    association :user, :confirmed
    first_name { FFaker::Name.first_name }
    last_name { FFaker::Name.last_name }
    gender { Profile::GENDERS.sample }
    birth_date { 30.years.ago.to_date }
  end
end
