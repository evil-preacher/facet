class DynamicStateObservation < ApplicationRecord
  belongs_to :personality
  belongs_to :generation_run

  validates :generation_run_id, uniqueness: true
  validates :rules_version, numericality: { only_integer: true, greater_than: 0 }
  validate :same_personality

  private

  def same_personality
    return if generation_run.nil? || personality.nil?
    return if generation_run.conversation_thread.personality_id == personality_id

    errors.add(:generation_run, :invalid)
  end
end
