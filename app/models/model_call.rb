class ModelCall < ApplicationRecord
  PURPOSES = %w[
    conversation
    memory_extraction
    memory_consolidation
    thread_summary
    initiative
    photo_planning
  ].freeze
  STATUSES = %w[pending completed failed].freeze

  belongs_to :user
  belongs_to :personality, optional: true
  belongs_to :generation_run, optional: true
  has_one :memory_extraction, dependent: :nullify

  enum :purpose, PURPOSES.index_with(&:itself), validate: true
  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :provider, :model, presence: true
  validates :response_model, length: { maximum: 120 }, allow_nil: true
  validates :input_tokens,
            :cached_input_tokens,
            :output_tokens,
            :cost_microusd,
            :latency_ms,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validate :cached_input_is_part_of_input
  validate :completed_call_has_usage_and_price
  validate :references_share_owner

  private

  def cached_input_is_part_of_input
    return if cached_input_tokens.nil? || input_tokens.nil?
    return if cached_input_tokens <= input_tokens

    errors.add(:cached_input_tokens, :less_than_or_equal_to, count: input_tokens)
  end

  def completed_call_has_usage_and_price
    return unless completed?

    %i[input_tokens cached_input_tokens output_tokens cost_microusd pricing_version completed_at].each do |attribute|
      errors.add(attribute, :blank) if public_send(attribute).nil?
    end
  end

  def references_share_owner
    errors.add(:personality, :invalid) if personality && personality.user_id != user_id
    return unless generation_run && personality
    return if generation_run.conversation_thread.personality_id == personality_id

    errors.add(:generation_run, :invalid)
  end
end
