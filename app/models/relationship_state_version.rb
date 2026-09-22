class RelationshipStateVersion < ApplicationRecord
  REASONS = %w[model_update rollback].freeze

  belongs_to :relationship_state, inverse_of: :versions
  belongs_to :generation_run, optional: true
  belongs_to :source_version, class_name: "RelationshipStateVersion", optional: true
  belongs_to :model_call, optional: true

  enum :reason, REASONS.index_with(&:itself), validate: true
  validates :revision, numericality: { only_integer: true, greater_than: 0 },
                       uniqueness: { scope: :relationship_state_id }
  validates :summary, presence: true, length: { maximum: 100_000 }
  validate :references_belong_to_personality
  validate :source_message_ids_are_owned

  private

  def references_belong_to_personality
    personality_id = relationship_state&.personality_id
    errors.add(:generation_run, :invalid) if generation_run &&
      generation_run.conversation_thread.personality_id != personality_id
    errors.add(:source_version, :invalid) if source_version &&
      source_version.relationship_state_id != relationship_state_id
  end

  def source_message_ids_are_owned
    ids = Array(source_message_ids)
    return if rollback? && ids.empty?
    return errors.add(:source_message_ids, :blank) if ids.empty?
    return errors.add(:source_message_ids, :invalid) unless ids.all? { |id| id.is_a?(Integer) }

    owned_count = Message.joins(:conversation_thread)
      .where(id: ids.uniq, conversation_threads: { personality_id: relationship_state.personality_id }).count
    errors.add(:source_message_ids, :invalid) unless owned_count == ids.uniq.length
  end
end
