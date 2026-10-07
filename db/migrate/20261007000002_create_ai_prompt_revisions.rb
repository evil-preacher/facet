class CreateAiPromptRevisions < ActiveRecord::Migration[8.1]
  def change
    create_table :ai_prompt_revisions do |t|
      t.string :key, null: false
      t.integer :revision, null: false
      t.text :content, null: false
      t.string :checksum, null: false
      t.string :status, null: false, default: "active"
      t.references :published_by, foreign_key: { to_table: :users, on_delete: :nullify }
      t.timestamps
    end
    add_index :ai_prompt_revisions, %i[key revision], unique: true
    add_index :ai_prompt_revisions, :key, unique: true, where: "status = 'active'", name: "index_ai_prompt_revisions_active_key"
    add_check_constraint :ai_prompt_revisions, "status IN ('active', 'retired')", name: "ai_prompt_revisions_status"
    add_check_constraint :ai_prompt_revisions, "revision > 0", name: "ai_prompt_revisions_positive_revision"
    add_check_constraint :ai_prompt_revisions, "char_length(btrim(content)) BETWEEN 1 AND 100000", name: "ai_prompt_revisions_content_length"
    remove_check_constraint :admin_audit_events, name: "admin_audit_events_action"
    add_check_constraint :admin_audit_events,
                         "action IN ('index', 'show', 'disable_initiative', 'retry_pending', 'publish_prompt')",
                         name: "admin_audit_events_action"
  end
end
