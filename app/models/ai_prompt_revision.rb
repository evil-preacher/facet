require "digest"

class AiPromptRevision < ApplicationRecord
  STATUSES = %w[active retired].freeze

  belongs_to :published_by, class_name: "User", optional: true

  enum :status, STATUSES.index_with(&:itself), prefix: true, validate: true
  attr_readonly :key, :revision, :content, :checksum, :published_by_id

  before_validation :assign_checksum

  validates :key, inclusion: { in: ->(_) { Ai::PromptCatalog::KEYS } }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }, uniqueness: { scope: :key }
  validates :content, presence: true, length: { maximum: 100_000 }
  validates :checksum, length: { is: 64 }
  validates :key, uniqueness: { conditions: -> { where(status: "active") }, if: :status_active? }
  validate :valid_placeholders

  scope :active, -> { where(status: "active") }

  private

  def assign_checksum
    self.checksum = Digest::SHA256.hexdigest(content.to_s) if new_record?
  end

  def valid_placeholders
    return unless Ai::PromptCatalog::KEYS.include?(key)

    expected = Ai::PromptCatalog::VARIABLES.fetch(key)
    actual = Ai::PromptCatalog.placeholders(content)
    unknown = actual - expected
    missing = expected - actual
    errors.add(:content, "has unknown placeholders: #{unknown.join(', ')}") if unknown.any?
    errors.add(:content, "is missing placeholders: #{missing.join(', ')}") if missing.any?
  end
end
