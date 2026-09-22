FactoryBot.define do
  factory :memory do
    personality { association :personality, :active }
    kind { :fact }
    sequence(:content) { |number| "Remembered fact #{number}" }
    importance { 50 }
    status { :active }
    origin { :model }
    sensitivity { :normal }
  end
end
