class InitiativeAttempt < ApplicationRecord
  STATUSES = %w[pending running completed skipped failed].freeze

  belongs_to :personality
  belongs_to :conversation_thread
  belongs_to :personality_version
  belongs_to :source_message, class_name: "Message"
  belongs_to :message, optional: true
  belongs_to :dynamic_state_revision, optional: true
  has_one :initiative_email_delivery, dependent: :destroy

  enum :status, STATUSES.index_with(&:itself), validate: true
  validates :topic, length: { maximum: 240 }, allow_nil: true
  validates :ai_provider, inclusion: { in: AiPlatformPrompt::PROVIDERS }
  validates :decision, inclusion: { in: %w[NO_ACTION IN_APP EMAIL] }, allow_nil: true
  validates :intensity, inclusion: { in: %w[low medium high] }, allow_nil: true
  validates :motivation, length: { maximum: 240 }, allow_nil: true
  validates :decision_reason, length: { maximum: 80 }, allow_nil: true
  validate :thread_belongs_to_personality
  validate :context_matches_thread

  after_commit :emit_status_telemetry, if: :saved_change_to_status?
  after_commit :emit_decision_telemetry, if: :saved_change_to_decision?

  def email_delivery_status
    initiative_email_delivery&.status
  end

  private

  def emit_decision_telemetry
    Operations::Telemetry.emit("initiative_decision", record_id: id, decision: decision,
                               decision_reason: decision_reason, intensity: intensity,
                               personality_id: personality_id, dynamic_state_revision_id: dynamic_state_revision_id)
  end

  def emit_status_telemetry
    Operations::Telemetry.emit("initiative", record_id: id, status: status,
                               provider: ai_provider, error_code: error_code,
                               personality_id: personality_id)
  end

  def thread_belongs_to_personality
    return if conversation_thread.nil? || personality.nil?
    return if conversation_thread.personality_id == personality.id

    errors.add(:conversation_thread, :invalid)
  end

  def context_matches_thread
    return if conversation_thread.nil?

    errors.add(:source_message, :invalid) if source_message && source_message.conversation_thread_id != conversation_thread.id
    errors.add(:personality_version, :invalid) if personality_version &&
      personality_version.personality_id != conversation_thread.personality_id
    errors.add(:message, :invalid) if message && message.conversation_thread_id != conversation_thread.id
    errors.add(:dynamic_state_revision, :invalid) if dynamic_state_revision &&
      dynamic_state_revision.relationship_state.personality_id != personality_id
  end
end
