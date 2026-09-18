class ConversationThread < ApplicationRecord
  STATUSES = %w[active archived].freeze

  belongs_to :personality
  has_many :generation_runs, dependent: :destroy
  has_many :messages,
           -> { order(position: :asc) },
           dependent: :destroy,
           inverse_of: :conversation_thread

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :title, length: { maximum: 120 }, allow_nil: true

  scope :recent_first, lambda {
    order(
      Arel.sql("CASE status WHEN 'active' THEN 0 ELSE 1 END"),
      Arel.sql("last_message_at DESC NULLS LAST"),
      created_at: :desc
    )
  }
end
