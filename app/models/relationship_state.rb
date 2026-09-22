class RelationshipState < ApplicationRecord
  belongs_to :personality
  has_many :versions, -> { order(revision: :asc) },
           class_name: "RelationshipStateVersion", dependent: :destroy, inverse_of: :relationship_state

  validates :personality_id, uniqueness: true
  validates :summary, length: { maximum: 100_000 }
  validates :revision, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
end
