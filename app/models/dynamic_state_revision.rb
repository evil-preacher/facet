class DynamicStateRevision < ApplicationRecord
  belongs_to :relationship_state, inverse_of: :dynamic_revisions
  belongs_to :generation_run, optional: true
  belongs_to :source_revision, class_name: "DynamicStateRevision", optional: true

  validates :revision, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :relationship_state_id }
  validates :rules_version, numericality: { only_integer: true, greater_than: 0 }
  validates :event_kind, presence: true
  validates :event_kind, inclusion: { in: %w[trust conflict repair closeness time_decay reset rollback] }
  validate :owned_sources

  private

  def owned_sources
    personality_id = relationship_state&.personality_id
    return if personality_id.nil?

    if generation_run && generation_run.conversation_thread.personality_id != personality_id
      errors.add(:generation_run, :invalid)
    end
    if source_revision && source_revision.relationship_state_id != relationship_state_id
      errors.add(:source_revision, :invalid)
    end
    ids = Array(source_message_ids)
    return if ids.empty?

    count = Message.joins(:conversation_thread)
      .where(id: ids.uniq, conversation_threads: { personality_id: personality_id }).count
    errors.add(:source_message_ids, :invalid) unless ids.all? { |id| id.is_a?(Integer) } && count == ids.uniq.size
  end
end
