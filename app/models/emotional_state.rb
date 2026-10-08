class EmotionalState < ApplicationRecord
  belongs_to :personality

  validates :personality_id, uniqueness: true
  %i[warmth irritation].each do |attribute|
    validates attribute, numericality: { only_integer: true, in: 0..100 }
  end
end
