class ConversationThread < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :personality
  belongs_to :summary_through_message, class_name: "Message", optional: true
  has_many :generation_runs, dependent: :destroy
  has_many :messages,
           -> { order(position: :asc) },
           dependent: :destroy,
           inverse_of: :conversation_thread

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :title, length: { maximum: 120 }, allow_nil: true
  validates :summary, length: { maximum: 100_000 }, allow_nil: true
  validate :summary_boundary_belongs_to_thread

  scope :recent_first, lambda {
    order(
      Arel.sql("CASE status WHEN 'active' THEN 0 ELSE 1 END"),
      Arel.sql("last_message_at DESC NULLS LAST"),
      created_at: :desc
    )
  }

  private

  def summary_boundary_belongs_to_thread
    return if summary_through_message.nil?
    return if summary_through_message.conversation_thread_id == id

    errors.add(:summary_through_message, :invalid)
  end
end
