require "digest"

class AiPlatformPrompt < ApplicationRecord
  PROVIDERS = %w[mistral openai].freeze
  PURPOSES = %w[conversation].freeze
  STATUSES = %w[active retired].freeze
  MAX_CONTENT_LENGTH = 20_000

  has_many :generation_runs, dependent: :nullify, inverse_of: :ai_platform_prompt

  attr_readonly :provider, :purpose, :revision, :content, :checksum, :published_at

  enum :status, STATUSES.index_with(&:itself), prefix: true, validate: true

  normalizes :provider, :purpose, with: ->(value) { value.to_s.strip.downcase }
  normalizes :content, with: ->(value) { value.to_s.strip }

  before_validation :assign_checksum

  validates :provider, inclusion: { in: PROVIDERS }
  validates :purpose, inclusion: { in: PURPOSES }
  validates :revision, numericality: { only_integer: true, greater_than: 0 }
  validates :revision, uniqueness: { scope: %i[provider purpose] }
  validates :content, presence: true, length: { maximum: MAX_CONTENT_LENGTH }
  validates :checksum, presence: true, length: { is: 64 }
  validates :published_at, presence: true, if: :status_active?
  validates :provider, uniqueness: {
    scope: :purpose,
    conditions: -> { where(status: "active") },
    if: :status_active?
  }

  scope :active, -> { where(status: "active") }

  def self.active_for(provider:, purpose: "conversation")
    active.find_by(provider: provider.to_s.downcase, purpose: purpose.to_s.downcase)
  end

  private

  def assign_checksum
    return unless new_record? || will_save_change_to_content?

    self.checksum = Digest::SHA256.hexdigest(content.to_s.strip)
  end
end
