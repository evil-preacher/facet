class Personality < ApplicationRecord
  STATUSES = %w[draft active archived].freeze
  AVATAR_STATUSES = %w[missing pending generating ready failed].freeze

  belongs_to :user
  belongs_to :current_version, class_name: "PersonalityVersion", optional: true
  belongs_to :avatar_source_version, class_name: "PersonalityVersion", optional: true
  has_many :conversation_threads, dependent: :destroy
  has_many :memories, dependent: :destroy
  has_many :memory_extractions, dependent: :destroy
  has_one :relationship_state, dependent: :destroy
  has_one :emotional_state, dependent: :destroy
  has_many :dynamic_state_observations, dependent: :destroy
  has_many :model_calls, dependent: :nullify
  has_many :initiative_attempts, dependent: :destroy
  has_many :versions,
           -> { order(number: :asc) },
           class_name: "PersonalityVersion",
           dependent: :destroy,
           inverse_of: :personality

  enum :status, STATUSES.index_with(&:itself), validate: true
  enum :avatar_status, AVATAR_STATUSES.index_with(&:itself), prefix: :avatar, validate: true

  validates :name, presence: true, length: { maximum: 80 }
  validates :description, length: { maximum: 500 }
  validates :conversation_model, :utility_model, presence: true, length: { maximum: 120 }
  validates :avatar_byte_size, :avatar_attempts_count,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }, allow_nil: true
  validates :initiative_idle_hours, numericality: { only_integer: true, in: 12..168 }
  validates :initiative_cooldown_hours, numericality: { only_integer: true, in: 24..720 }
  validates :initiative_intensity, inclusion: { in: %w[quiet normal expressive] }
  validates :initiative_quiet_start_hour, :initiative_quiet_end_hour,
            numericality: { only_integer: true, in: 0..23 }
  validate :valid_initiative_timezone
  validate :distinct_quiet_hours
  validate :current_version_belongs_to_personality
  validate :current_version_present_when_active
  validate :avatar_source_version_belongs_to_personality
  validate :ready_avatar_has_metadata

  private

  def valid_initiative_timezone
    errors.add(:initiative_timezone, :invalid) unless ActiveSupport::TimeZone[initiative_timezone]
  end

  def distinct_quiet_hours
    errors.add(:initiative_quiet_end_hour, :invalid) if initiative_quiet_start_hour == initiative_quiet_end_hour
  end

  def current_version_present_when_active
    errors.add(:current_version, :blank) if active? && current_version.nil?
  end

  def current_version_belongs_to_personality
    return if current_version.nil? || current_version.personality == self

    errors.add(:current_version, :invalid)
  end

  def avatar_source_version_belongs_to_personality
    return if avatar_source_version.nil? || avatar_source_version.personality == self

    errors.add(:avatar_source_version, :invalid)
  end

  def ready_avatar_has_metadata
    return unless avatar_ready?

    {
      avatar_object_key: avatar_object_key,
      avatar_content_type: avatar_content_type,
      avatar_byte_size: avatar_byte_size,
      avatar_generated_at: avatar_generated_at,
      avatar_source_version: avatar_source_version
    }.each { |attribute, value| errors.add(attribute, :blank) if value.nil? }
  end
end
