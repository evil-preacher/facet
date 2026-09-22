class Memory < ApplicationRecord
  KINDS = %w[fact preference shared_event relationship boundary other].freeze
  STATUSES = %w[active pending superseded deleted].freeze
  ORIGINS = %w[model user].freeze
  SENSITIVITIES = %w[normal sensitive].freeze
  MAX_CONTENT_LENGTH = 500

  belongs_to :personality
  belongs_to :supersedes, class_name: "Memory", optional: true
  has_one :superseding_memory,
          class_name: "Memory",
          foreign_key: :supersedes_id,
          dependent: :nullify,
          inverse_of: :supersedes
  has_many :memory_sources, dependent: :destroy, inverse_of: :memory
  has_many :source_messages, through: :memory_sources, source: :message

  enum :kind, KINDS.index_with(&:itself), validate: true
  enum :status, STATUSES.index_with(&:itself), validate: true
  enum :origin, ORIGINS.index_with(&:itself), prefix: true, validate: true
  enum :sensitivity, SENSITIVITIES.index_with(&:itself), validate: true

  before_validation :normalize_content

  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validates :normalized_content, presence: true
  validates :importance, numericality: { only_integer: true, in: 1..100 }
  validates :normalized_content,
            uniqueness: {
              scope: %i[personality_id kind],
              conditions: -> { where(status: %w[active pending]) }
            },
            if: -> { active? || pending? }
  validate :superseded_memory_belongs_to_personality
  validate :deleted_at_matches_status

  scope :current, -> { where(status: %w[active pending]) }
  scope :available_for_retrieval, -> { active }

  def self.normalize(value)
    value.to_s.unicode_normalize(:nfkc).squish.downcase
  end

  private

  def normalize_content
    self.content = content.to_s.squish
    self.normalized_content = self.class.normalize(content)
  end

  def superseded_memory_belongs_to_personality
    return unless supersedes
    return if supersedes.personality_id == personality_id && supersedes_id != id

    errors.add(:supersedes, :invalid)
  end

  def deleted_at_matches_status
    errors.add(:deleted_at, :blank) if deleted? && deleted_at.nil?
    errors.add(:deleted_at, :present) if !deleted? && deleted_at.present?
  end
end
