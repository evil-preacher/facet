FactoryBot.define do
  factory :message_image do
    association :message, factory: [ :message, :assistant ], status: :streaming, content: ""
    status { :pending }
    source_avatar_object_key { "personalities/1/avatars/version-1.jpg" }
  end
end
