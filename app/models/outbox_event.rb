class OutboxEvent < ApplicationRecord
  STATUSES = %w[pending processing dispatched].freeze

  enum :status, STATUSES.index_with(&:itself), validate: true

  validates :event_key, :job_class, :queue_name, :available_at, presence: true
  validates :event_key, uniqueness: true
  validates :attempts_count, numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :arguments_are_an_array

  scope :ready, ->(now = Time.current) { where(status: :pending, available_at: ..now) }

  private

  def arguments_are_an_array
    errors.add(:arguments, :invalid) unless arguments.is_a?(Array)
  end
end
