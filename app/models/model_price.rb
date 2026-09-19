class ModelPrice < ApplicationRecord
  validates :provider, :model, :version, :effective_from, presence: true
  validates :effective_from, uniqueness: { scope: %i[provider model] }
  validates :input_microusd_per_million,
            :cached_input_microusd_per_million,
            :output_microusd_per_million,
            numericality: { only_integer: true, greater_than_or_equal_to: 0 }
  validate :effective_interval_is_ordered

  scope :for_instant, lambda { |instant|
    where("effective_from <= ?", instant)
      .where("effective_until IS NULL OR effective_until > ?", instant)
  }

  def self.current_for(provider:, model:, at: Time.current)
    where(provider: provider, model: model)
      .for_instant(at)
      .order(effective_from: :desc)
      .first
  end

  private

  def effective_interval_is_ordered
    return if effective_until.nil? || effective_from.nil? || effective_until > effective_from

    errors.add(:effective_until, :greater_than, count: effective_from)
  end
end
