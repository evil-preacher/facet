require "administrate/base_dashboard"

class ModelCallDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user_id: Field::Number,
    personality_id: Field::Number,
    generation_run_id: Field::Number,
    provider: Field::String,
    model: Field::String,
    purpose: Field::String,
    status: Field::String,
    input_tokens: Field::Number,
    cached_input_tokens: Field::Number,
    output_tokens: Field::Number,
    cost_microusd: Field::Number,
    error_code: Field::String,
    created_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[id user_id provider model purpose status cost_microusd].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
