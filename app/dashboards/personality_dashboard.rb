require "administrate/base_dashboard"

class PersonalityDashboard < Administrate::BaseDashboard
  ATTRIBUTE_TYPES = {
    id: Field::Number,
    user_id: Field::Number,
    name: Field::String,
    status: Field::String,
    initiative_enabled: Field::Boolean,
    initiative_idle_hours: Field::Number,
    initiative_cooldown_hours: Field::Number,
    created_at: Field::DateTime
  }.freeze
  COLLECTION_ATTRIBUTES = %i[id user_id name status initiative_enabled].freeze
  SHOW_PAGE_ATTRIBUTES = ATTRIBUTE_TYPES.keys.freeze
  FORM_ATTRIBUTES = [].freeze
  COLLECTION_FILTERS = {}.freeze
end
