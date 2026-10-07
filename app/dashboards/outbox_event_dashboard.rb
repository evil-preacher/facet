require "administrate/base_dashboard"

class OutboxEventDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    job_class: Field::String,
    queue_name: Field::String,
    status: Field::String,
    attempts_count: Field::Number,
    available_at: Field::DateTime,
    created_at: Field::DateTime,
    dispatched_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[id job_class status attempts_count created_at].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
