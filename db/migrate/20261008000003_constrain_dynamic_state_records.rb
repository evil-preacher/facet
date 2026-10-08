class ConstrainDynamicStateRecords < ActiveRecord::Migration[8.1]
  def change
    add_check_constraint :dynamic_state_revisions,
                         "event_kind IN ('trust', 'conflict', 'repair', 'closeness', 'time_decay', 'reset', 'rollback')",
                         name: "dynamic_state_revisions_event_kind"
    add_check_constraint :dynamic_state_revisions,
                         "jsonb_typeof(slow_state) = 'object' AND jsonb_typeof(fast_state) = 'object' " \
                         "AND jsonb_typeof(source_message_ids) = 'array'",
                         name: "dynamic_state_revisions_json_shapes"
    add_check_constraint :dynamic_state_observations, "jsonb_typeof(extraction) = 'object'",
                         name: "dynamic_state_observations_extraction_object"
  end
end
