class MemoryExtraction < ApplicationRecord
  STATUSES = %w[pending running completed failed skipped].freeze

  belongs_to :personality
  belongs_to :generation_run
  belongs_to :model_call, optional: true

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :generation_run_id, uniqueness: true
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :generation_run_belongs_to_personality
  validate :model_call_belongs_to_personality

  after_commit :emit_status_telemetry, if: :saved_change_to_status?

  private

  def emit_status_telemetry
    Operations::Telemetry.emit("memory_extraction", record_id: id, status: status,
                               error_code: error_code, attempts_count: attempts_count,
                               generation_run_id: generation_run_id)
  end

  def generation_run_belongs_to_personality
    return if generation_run.nil? || personality.nil?
    return if generation_run.conversation_thread.personality_id == personality_id

    errors.add(:generation_run, :invalid)
  end

  def model_call_belongs_to_personality
    return if model_call.nil? || personality.nil?
    return if model_call.personality_id == personality_id && model_call.memory_extraction?

    errors.add(:model_call, :invalid)
  end
end
