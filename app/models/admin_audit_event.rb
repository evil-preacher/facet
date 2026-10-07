class AdminAuditEvent < ApplicationRecord
  ACTIONS = %w[index show disable_initiative retry_pending publish_prompt publish_platform_prompt].freeze

  validates :actor_user_id, :target_type, presence: true
  validates :action, inclusion: { in: ACTIONS }
  validates :target_id, numericality: { only_integer: true, greater_than: 0 }, allow_nil: true
end
