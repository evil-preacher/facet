class GenerationRun < ApplicationRecord
  STATUSES = %w[pending running completed failed stopped].freeze

  belongs_to :conversation_thread
  belongs_to :personality_version
  belongs_to :user_message, class_name: "Message", inverse_of: :generation_runs_as_user
  belongs_to :assistant_message, class_name: "Message", optional: true, inverse_of: :generation_run_as_assistant
  belongs_to :retry_of, class_name: "GenerationRun", optional: true, inverse_of: :retry_run
  belongs_to :ai_platform_prompt, optional: true, inverse_of: :generation_runs
  has_one :retry_run,
          class_name: "GenerationRun",
          foreign_key: :retry_of_id,
          dependent: :restrict_with_exception,
          inverse_of: :retry_of
  has_many :model_calls, dependent: :nullify
  has_one :memory_extraction, dependent: :destroy
  has_one :thread_summary_version, dependent: :destroy
  has_one :relationship_state_version, dependent: :nullify

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :idempotency_key, presence: true, uniqueness: true
  validates :assistant_message_id, uniqueness: true, allow_nil: true
  validates :retry_of_id, uniqueness: true, allow_nil: true
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validates :ai_provider, inclusion: { in: AiPlatformPrompt::PROVIDERS }
  validate :messages_match_thread_and_roles
  validate :personality_version_matches_thread
  validate :platform_prompt_matches_provider

  after_commit :emit_status_telemetry, if: :saved_change_to_status?

  private

  def emit_status_telemetry
    Operations::Telemetry.emit(
      "generation_run", record_id: id, status: status, provider: ai_provider,
      error_code: error_code, attempts_count: attempts_count,
      first_token_latency_ms: prompt_manifest["first_token_latency_ms"]
    )
  end

  def messages_match_thread_and_roles
    validate_message(user_message, :user_message, "user")
    validate_message(assistant_message, :assistant_message, "assistant") if assistant_message
  end

  def validate_message(message, attribute, expected_role)
    return if message.nil?

    errors.add(attribute, :invalid) unless message.conversation_thread_id == conversation_thread_id
    errors.add(attribute, :invalid) unless message.role == expected_role
  end

  def personality_version_matches_thread
    return if personality_version.nil? || conversation_thread.nil?
    return if personality_version.personality_id == conversation_thread.personality_id

    errors.add(:personality_version, :invalid)
  end

  def platform_prompt_matches_provider
    return unless ai_platform_prompt
    return if ai_platform_prompt.provider == ai_provider && ai_platform_prompt.purpose == "conversation"

    errors.add(:ai_platform_prompt, :invalid)
  end
end
