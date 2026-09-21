FactoryBot.define do
  factory :message_attachment do
    association :message
    sequence(:object_key) { |number| "messages/attachments/test-#{number}.jpg" }
    content_type { "image/jpeg" }
    byte_size { 100 }
    original_filename { "photo.jpg" }
  end
end
