class ThreadSummaryVersion < ApplicationRecord
  belongs_to :conversation_thread
  belongs_to :generation_run
  belongs_to :through_message, class_name: "Message"
  belongs_to :previous_version, class_name: "ThreadSummaryVersion", optional: true
  belongs_to :model_call, optional: true

  validates :revision, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :conversation_thread_id }
  validates :summary, presence: true, length: { maximum: 100_000 }
  validate :references_belong_to_thread
  validate :source_messages_belong_to_thread

  private

  def references_belong_to_thread
    return unless conversation_thread

    errors.add(:generation_run, :invalid) if generation_run&.conversation_thread_id != conversation_thread_id
    errors.add(:through_message, :invalid) if through_message&.conversation_thread_id != conversation_thread_id
    errors.add(:previous_version, :invalid) if previous_version &&
      previous_version.conversation_thread_id != conversation_thread_id
  end

  def source_messages_belong_to_thread
    ids = Array(source_message_ids)
    return errors.add(:source_message_ids, :blank) if ids.empty?
    return errors.add(:source_message_ids, :invalid) unless ids.all? { |id| id.is_a?(Integer) }

    errors.add(:source_message_ids, :invalid) unless conversation_thread.messages.where(id: ids.uniq).count == ids.uniq.length
  end
end
