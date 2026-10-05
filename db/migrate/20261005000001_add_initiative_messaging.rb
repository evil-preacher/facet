class AddInitiativeMessaging < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :initiative_enabled, :boolean, null: false, default: false
    add_column :personalities, :initiative_idle_hours, :integer, null: false, default: 24
    add_column :personalities, :initiative_cooldown_hours, :integer, null: false, default: 72
    add_check_constraint :personalities, "initiative_idle_hours BETWEEN 12 AND 168", name: "personalities_initiative_idle_hours"
    add_check_constraint :personalities, "initiative_cooldown_hours BETWEEN 24 AND 720", name: "personalities_initiative_cooldown_hours"
    add_index :personalities, %i[initiative_enabled status]

    add_column :messages, :initiated_by, :string
    add_column :messages, :read_at, :datetime
    add_check_constraint :messages,
                         "(initiated_by IS NULL AND read_at IS NULL) OR (initiated_by = 'personality' AND role = 'assistant')",
                         name: "messages_initiative_metadata"
    add_index :messages, %i[conversation_thread_id read_at],
              where: "initiated_by = 'personality' AND read_at IS NULL", name: "index_unread_initiative_messages"

    create_table :initiative_attempts do |t|
      t.references :personality, null: false, foreign_key: { on_delete: :cascade }
      t.references :conversation_thread, null: false, foreign_key: { on_delete: :cascade }
      t.references :personality_version, null: false, foreign_key: { on_delete: :restrict }
      t.references :source_message, null: false, foreign_key: { to_table: :messages, on_delete: :cascade }
      t.references :message, foreign_key: { on_delete: :nullify }
      t.string :ai_provider, null: false
      t.string :status, null: false, default: "pending"
      t.string :topic
      t.string :error_code
      t.datetime :started_at
      t.datetime :completed_at
      t.timestamps
    end
    add_index :initiative_attempts, :personality_id, unique: true,
              where: "status IN ('pending', 'running')", name: "index_active_initiative_attempts"
    add_check_constraint :initiative_attempts,
                         "status IN ('pending', 'running', 'completed', 'skipped', 'failed')",
                         name: "initiative_attempts_status"
  end
end
