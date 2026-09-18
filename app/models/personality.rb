class Personality < ApplicationRecord
  STATUSES = %w[draft active archived].freeze

  belongs_to :user
  belongs_to :current_version, class_name: "PersonalityVersion", optional: true
  has_many :conversation_threads, dependent: :destroy
  has_many :versions,
           -> { order(number: :asc) },
           class_name: "PersonalityVersion",
           dependent: :destroy,
           inverse_of: :personality

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 500 }
  validate :current_version_belongs_to_personality
  validate :current_version_present_when_active

  private

  def current_version_present_when_active
    errors.add(:current_version, :blank) if active? && current_version.nil?
  end

  def current_version_belongs_to_personality
    return if current_version.nil? || current_version.personality == self

    errors.add(:current_version, :invalid)
  end
end
