class AddRetrievalSummariesAndRelationshipStates < ActiveRecord::Migration[8.1]
  def change
    create_table :thread_summary_versions do |t|
      t.references :conversation_thread, null: false, foreign_key: { on_delete: :cascade }
      t.references :generation_run, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :through_message, null: false, foreign_key: { to_table: :messages, on_delete: :restrict }
      t.references :previous_version, foreign_key: { to_table: :thread_summary_versions, on_delete: :nullify }
      t.references :model_call, foreign_key: { on_delete: :nullify }
      t.integer :revision, null: false
      t.text :summary, null: false
      t.jsonb :source_message_ids, null: false, default: []
      t.timestamps
    end
    add_index :thread_summary_versions, %i[conversation_thread_id revision], unique: true,
              name: "index_thread_summary_versions_on_thread_and_revision"
    add_check_constraint :thread_summary_versions, "revision > 0", name: "thread_summary_versions_revision"
    add_check_constraint :thread_summary_versions, "char_length(btrim(summary)) BETWEEN 1 AND 100000",
                         name: "thread_summary_versions_summary_length"

    create_table :relationship_states do |t|
      t.references :personality, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.text :summary, null: false, default: ""
      t.integer :revision, null: false, default: 0
      t.timestamps
    end
    add_check_constraint :relationship_states, "revision >= 0", name: "relationship_states_revision"
    add_check_constraint :relationship_states, "char_length(summary) <= 100000",
                         name: "relationship_states_summary_length"

    create_table :relationship_state_versions do |t|
      t.references :relationship_state, null: false, foreign_key: { on_delete: :cascade }
      t.references :generation_run, foreign_key: { on_delete: :nullify }, index: { unique: true }
      t.references :source_version, foreign_key: { to_table: :relationship_state_versions, on_delete: :nullify }
      t.references :model_call, foreign_key: { on_delete: :nullify }
      t.integer :revision, null: false
      t.text :summary, null: false
      t.jsonb :source_message_ids, null: false, default: []
      t.string :reason, null: false, default: "model_update"
      t.timestamps
    end
    add_index :relationship_state_versions, %i[relationship_state_id revision], unique: true,
              name: "index_relationship_versions_on_state_and_revision"
    add_check_constraint :relationship_state_versions, "revision > 0", name: "relationship_state_versions_revision"
    add_check_constraint :relationship_state_versions, "reason IN ('model_update', 'rollback')",
                         name: "relationship_state_versions_reason"
    add_check_constraint :relationship_state_versions, "char_length(btrim(summary)) BETWEEN 1 AND 100000",
                         name: "relationship_state_versions_summary_length"
  end
end
