class InitiativeAttempt < ApplicationRecord
  STATUSES = %w[pending running completed skipped failed].freeze

  belongs_to :personality
  belongs_to :conversation_thread
  belongs_to :personality_version
  belongs_to :source_message, class_name: "Message"
  belongs_to :message, optional: true

  enum :status, STATUSES.index_with(&:itself), validate: true
  validates :topic, length: { maximum: 240 }, allow_nil: true
  validates :ai_provider, inclusion: { in: AiPlatformPrompt::PROVIDERS }
  validate :thread_belongs_to_personality
  validate :context_matches_thread

  private

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
  end
end
