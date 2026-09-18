class PersonalityVersion < ApplicationRecord
  MAX_CONTENT_LENGTH = 20_000

  belongs_to :personality, inverse_of: :versions
  belongs_to :source_version, class_name: "PersonalityVersion", optional: true

  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validates :number,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :personality_id }
end
