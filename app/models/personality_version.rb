class PersonalityVersion < ApplicationRecord
  MAX_CONTENT_LENGTH = 20_000

  belongs_to :personality, inverse_of: :versions
  belongs_to :author, class_name: "User"
  belongs_to :source_version, class_name: "PersonalityVersion", optional: true
  has_many :messages, dependent: :restrict_with_exception
  has_many :generation_runs, dependent: :restrict_with_exception
  has_many :derived_versions,
           class_name: "PersonalityVersion",
           foreign_key: :source_version_id,
           dependent: :nullify,
           inverse_of: :source_version

  attr_readonly :personality_id, :author_id, :number, :content, :change_note, :source_version_id

  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validates :change_note, length: { maximum: 500 }, allow_nil: true
  validates :number,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :personality_id }
  validate :source_version_belongs_to_personality
  validate :author_owns_personality

  private

  def author_owns_personality
    return if author.nil? || author.id == personality&.user_id

    errors.add(:author, :invalid)
  end

  def source_version_belongs_to_personality
    return if source_version.nil? || source_version.personality_id == personality_id

    errors.add(:source_version, :invalid)
  end
end
