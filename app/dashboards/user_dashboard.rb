require "administrate/base_dashboard"

class UserDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    email: Field::String,
    confirmed_at: Field::DateTime,
    monthly_ai_limit_microusd: Field::Number,
    admin: Field::Boolean,
    created_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[id email confirmed_at monthly_ai_limit_microusd].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
