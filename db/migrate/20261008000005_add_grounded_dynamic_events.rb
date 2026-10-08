class AddGroundedDynamicEvents < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :dynamic_state_revisions, name: "dynamic_state_revisions_event_kind"
    add_check_constraint :dynamic_state_revisions,
                         "event_kind IN ('trust', 'conflict', 'repair', 'closeness', 'jealousy', 'attraction', 'space_request', 'time_decay', 'reset', 'rollback')",
                         name: "dynamic_state_revisions_event_kind"
  end
end
