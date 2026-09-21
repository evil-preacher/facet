class MessageAttachment < ApplicationRecord
  CONTENT_TYPES = %w[image/jpeg image/png image/webp].freeze
  MAX_BYTES = 10.megabytes

  belongs_to :message, inverse_of: :attachment

  validates :object_key, presence: true, uniqueness: true
  validates :content_type, inclusion: { in: CONTENT_TYPES }
  validates :byte_size,
            numericality: {
              only_integer: true,
              greater_than: 0,
              less_than_or_equal_to: MAX_BYTES
            }
  validates :original_filename, length: { maximum: 255 }, allow_nil: true
  validate :belongs_to_user_message

  private

  def belongs_to_user_message
    errors.add(:message, :invalid) if message && !message.user?
  end
end
