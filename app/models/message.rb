class Message < ApplicationRecord
  ROLES = %w[user assistant].freeze
  STATUSES = %w[streaming completed failed stopped].freeze
  MAX_CONTENT_LENGTH = 100_000
  CLIENT_TOKEN_FORMAT = /\A[0-9a-f]{8}-[0-9a-f]{4}-[1-5][0-9a-f]{3}-[89ab][0-9a-f]{3}-[0-9a-f]{12}\z/i

  belongs_to :conversation_thread, inverse_of: :messages
  belongs_to :personality_version
  has_many :generation_runs_as_user,
          class_name: "GenerationRun",
          foreign_key: :user_message_id,
          dependent: :restrict_with_exception,
          inverse_of: :user_message
  has_one :message_image, dependent: :destroy, inverse_of: :message
  has_one :generation_run_as_assistant,
          class_name: "GenerationRun",
          foreign_key: :assistant_message_id,
          dependent: :restrict_with_exception,
          inverse_of: :assistant_message

  enum :role, ROLES.index_with(&:itself), validate: true
  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :position,
            numericality: { only_integer: true, greater_than: 0 },
            uniqueness: { scope: :conversation_thread_id }
  validates :content, length: { maximum: MAX_CONTENT_LENGTH }
  validates :language, inclusion: { in: %w[ru en und] }
  validates :client_token,
            format: { with: CLIENT_TOKEN_FORMAT },
            uniqueness: true,
            allow_nil: true
  validate :completed_message_has_content
  validate :user_message_has_client_token
  validate :user_message_is_completed
  validate :personality_version_matches_thread

  private

  def completed_message_has_content
    errors.add(:content, :blank) if completed? && content.to_s.strip.blank?
  end

  def user_message_has_client_token
    errors.add(:client_token, :blank) if user? && client_token.blank?
  end

  def user_message_is_completed
    errors.add(:status, :invalid) if user? && !completed?
  end

  def personality_version_matches_thread
    return if personality_version.nil? || conversation_thread.nil?
    return if personality_version.personality_id == conversation_thread.personality_id

    errors.add(:personality_version, :invalid)
  end
end
