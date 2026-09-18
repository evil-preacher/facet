class CreateConversations < ActiveRecord::Migration[8.1]
  def change
    create_table :conversation_threads do |t|
      t.references :personality, null: false, foreign_key: true
      t.string :title
      t.string :status, null: false, default: "active"
      t.datetime :last_message_at

      t.timestamps
    end

    add_index :conversation_threads, %i[personality_id status last_message_at]
    add_check_constraint :conversation_threads,
                         "title IS NULL OR char_length(btrim(title)) BETWEEN 1 AND 120",
                         name: "conversation_threads_title_length"
    add_check_constraint :conversation_threads,
                         "status IN ('active', 'archived')",
                         name: "conversation_threads_status"

    create_table :messages do |t|
      t.references :conversation_thread, null: false, foreign_key: true
      t.references :personality_version, null: false, foreign_key: true
      t.integer :position, null: false
      t.string :role, null: false
      t.string :status, null: false, default: "completed"
      t.text :content, null: false, default: ""
      t.string :client_token

      t.timestamps
    end

    add_index :messages, %i[conversation_thread_id position], unique: true
    add_index :messages, :client_token,
              unique: true,
              where: "client_token IS NOT NULL"
    add_check_constraint :messages,
                         "position > 0",
                         name: "messages_positive_position"
    add_check_constraint :messages,
                         "role IN ('user', 'assistant')",
                         name: "messages_role"
    add_check_constraint :messages,
                         "status IN ('streaming', 'completed', 'failed')",
                         name: "messages_status"
    add_check_constraint :messages,
                         <<~SQL.squish,
                           char_length(content) <= 100000 AND
                           (status != 'completed' OR char_length(btrim(content)) > 0)
                         SQL
                         name: "messages_content"

    create_table :generation_runs do |t|
      t.references :conversation_thread, null: false, foreign_key: true
      t.references :personality_version, null: false, foreign_key: true
      t.bigint :user_message_id, null: false
      t.bigint :assistant_message_id
      t.string :idempotency_key, null: false
      t.string :status, null: false, default: "pending"
      t.integer :attempts_count, null: false, default: 0
      t.string :error_code
      t.text :error_message
      t.datetime :started_at
      t.datetime :completed_at

      t.timestamps
    end

    add_index :generation_runs, :user_message_id, unique: true
    add_index :generation_runs, :assistant_message_id,
              unique: true,
              where: "assistant_message_id IS NOT NULL"
    add_index :generation_runs, :idempotency_key, unique: true
    add_index :generation_runs, %i[conversation_thread_id status]
    add_check_constraint :generation_runs,
                         "status IN ('pending', 'running', 'completed', 'failed', 'stopped')",
                         name: "generation_runs_status"
    add_check_constraint :generation_runs,
                         "attempts_count >= 0",
                         name: "generation_runs_attempts_count"

    add_foreign_key :generation_runs,
                    :messages,
                    column: :user_message_id,
                    on_delete: :restrict
    add_foreign_key :generation_runs,
                    :messages,
                    column: :assistant_message_id,
                    on_delete: :restrict
  end
end
