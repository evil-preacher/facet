class MessageImage < ApplicationRecord
  STATUSES = %w[pending generating ready failed declined].freeze

  belongs_to :message, inverse_of: :message_image

  enum :status, STATUSES.index_with(&:itself), prefix: true, validate: true

  validates :source_avatar_object_key, presence: true
  validates :scene_description, length: { maximum: 4_000 }, allow_nil: true
  validates :attempts_count, :byte_size,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 },
            allow_nil: true
  validate :belongs_to_assistant_message
  validate :ready_image_has_metadata

  def mark_failed!(error_code:)
    return if status_ready? || status_declined?

    update!(
      status: :failed,
      started_at: nil,
      error_code: error_code,
      error_message: nil
    )
  end

  private

  def belongs_to_assistant_message
    errors.add(:message, :invalid) if message && !message.assistant?
  end

  def ready_image_has_metadata
    return unless status_ready?

    {
      object_key: object_key,
      content_type: content_type,
      byte_size: byte_size,
      generated_at: generated_at
    }.each { |attribute, value| errors.add(attribute, :blank) if value.nil? }
  end
end
