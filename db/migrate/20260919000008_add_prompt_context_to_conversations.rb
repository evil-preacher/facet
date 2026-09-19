class AddPromptContextToConversations < ActiveRecord::Migration[8.1]
  def change
    add_column :conversation_threads, :summary, :text
    add_column :conversation_threads, :summary_through_message_id, :bigint
    add_index :conversation_threads, :summary_through_message_id
    add_foreign_key :conversation_threads,
                    :messages,
                    column: :summary_through_message_id,
                    on_delete: :nullify
    add_check_constraint :conversation_threads,
                         "summary IS NULL OR char_length(summary) <= 100000",
                         name: "conversation_threads_summary_length"

    add_column :messages, :language, :string, null: false, default: "und"
    add_check_constraint :messages,
                         "language IN ('ru', 'en', 'und')",
                         name: "messages_language"

    add_column :generation_runs, :prompt_manifest, :jsonb, null: false, default: {}
  end
end
