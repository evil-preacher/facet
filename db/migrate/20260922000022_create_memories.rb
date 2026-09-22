class CreateMemories < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :automatic_memory_enabled, :boolean, null: false, default: true

    create_table :memory_extractions do |t|
      t.references :personality, null: false, foreign_key: { on_delete: :cascade }
      t.references :generation_run, null: false, foreign_key: { on_delete: :cascade }, index: { unique: true }
      t.references :model_call, foreign_key: { on_delete: :nullify }
      t.string :status, null: false, default: "pending"
      t.integer :attempts_count, null: false, default: 0
      t.datetime :started_at
      t.datetime :completed_at
      t.string :error_code
      t.text :error_message
      t.timestamps
    end

    add_check_constraint :memory_extractions,
                         "status IN ('pending', 'running', 'completed', 'failed', 'skipped')",
                         name: "memory_extractions_status"
    add_check_constraint :memory_extractions,
                         "attempts_count >= 0",
                         name: "memory_extractions_attempts_count"

    create_table :memories do |t|
      t.references :personality, null: false, foreign_key: { on_delete: :cascade }
      t.references :supersedes, foreign_key: { to_table: :memories, on_delete: :nullify }
      t.string :kind, null: false
      t.text :content, null: false
      t.text :normalized_content, null: false
      t.integer :importance, null: false
      t.string :status, null: false, default: "active"
      t.string :origin, null: false
      t.string :sensitivity, null: false, default: "normal"
      t.datetime :occurred_at
      t.datetime :last_recalled_at
      t.datetime :deleted_at
      t.timestamps
    end

    add_index :memories,
              %i[personality_id kind normalized_content],
              unique: true,
              where: "status IN ('active', 'pending')",
              name: "index_current_memories_on_normalized_content"
    add_index :memories, %i[personality_id status importance], name: "index_memories_for_management"
    add_check_constraint :memories,
                         "kind IN ('fact', 'preference', 'shared_event', 'relationship', 'boundary', 'other')",
                         name: "memories_kind"
    add_check_constraint :memories,
                         "status IN ('active', 'pending', 'superseded', 'deleted')",
                         name: "memories_status"
    add_check_constraint :memories,
                         "origin IN ('model', 'user')",
                         name: "memories_origin"
    add_check_constraint :memories,
                         "sensitivity IN ('normal', 'sensitive')",
                         name: "memories_sensitivity"
    add_check_constraint :memories,
                         "importance BETWEEN 1 AND 100",
                         name: "memories_importance"
    add_check_constraint :memories,
                         "char_length(btrim(content)) BETWEEN 1 AND 500",
                         name: "memories_content_length"
    add_check_constraint :memories,
                         "(status = 'deleted') = (deleted_at IS NOT NULL)",
                         name: "memories_deleted_at"

    create_table :memory_sources do |t|
      t.references :memory, null: false, foreign_key: { on_delete: :cascade }
      t.references :message, null: false, foreign_key: { on_delete: :cascade }
      t.timestamps
    end

    add_index :memory_sources, %i[memory_id message_id], unique: true
  end
end
