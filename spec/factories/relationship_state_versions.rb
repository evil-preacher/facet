FactoryBot.define do
  factory :relationship_state_version do
    relationship_state
    revision { relationship_state.versions.maximum(:revision).to_i + 1 }
    summary { relationship_state.summary.presence || "They are getting to know each other." }
    source_message_ids { [] }
    reason { :rollback }
  end
end
