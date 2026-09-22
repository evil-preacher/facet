class MemorySource < ApplicationRecord
  belongs_to :memory, inverse_of: :memory_sources
  belongs_to :message

  validates :message_id, uniqueness: { scope: :memory_id }
  validate :message_belongs_to_personality

  private

  def message_belongs_to_personality
    return if memory.nil? || message.nil?
    return if message.conversation_thread.personality_id == memory.personality_id

    errors.add(:message, :invalid)
  end
end
