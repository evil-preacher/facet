class TrackRelationshipContextWork < ActiveRecord::Migration[8.1]
  def change
    add_column :generation_runs, :relationship_update_processed_at, :datetime
    add_column :generation_runs, :relationship_consolidated_at, :datetime
    add_column :relationship_states, :last_consolidated_message_id, :bigint

    remove_check_constraint :relationship_state_versions, name: "relationship_state_versions_reason"
    add_check_constraint :relationship_state_versions,
                         "reason IN ('model_update', 'cleanup', 'consolidation', 'rollback')",
                         name: "relationship_state_versions_reason"
    remove_check_constraint :relationship_state_versions, name: "relationship_state_versions_summary_length"
    add_check_constraint :relationship_state_versions,
                         "char_length(summary) <= 100000",
                         name: "relationship_state_versions_summary_length"
  end
end
