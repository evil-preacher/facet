require "administrate/base_dashboard"

class InitiativeAttemptDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    personality_id: Field::Number,
    conversation_thread_id: Field::Number,
    status: Field::String,
    ai_provider: Field::String,
    error_code: Field::String,
    created_at: Field::DateTime,
    started_at: Field::DateTime,
    completed_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[id personality_id status ai_provider created_at].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
