class InitiativeEmailDelivery < ApplicationRecord
  STATUSES = %w[pending sending delivered failed suppressed unknown].freeze

  belongs_to :initiative_attempt
  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :initiative_attempt_id, uniqueness: true
  validates :email_message_id, uniqueness: true, allow_nil: true
  validates :error_code, length: { maximum: 80 }, allow_nil: true

  after_commit :emit_status_telemetry, if: :saved_change_to_status?

  private

  def emit_status_telemetry
    Operations::Telemetry.emit("initiative_email_delivery", record_id: id,
                               status: status, error_code: error_code,
                               personality_id: initiative_attempt.personality_id)
  end
end
