class AddStreamingLifecycle < ActiveRecord::Migration[8.1]
  def change
    remove_index :generation_runs, :user_message_id, unique: true
    add_index :generation_runs, :user_message_id
    add_reference :generation_runs,
                  :retry_of,
                  foreign_key: { to_table: :generation_runs, on_delete: :restrict },
                  index: { unique: true }

    remove_check_constraint :messages, name: "messages_status"
    add_check_constraint :messages,
                         "status IN ('streaming', 'completed', 'failed', 'stopped')",
                         name: "messages_status"
  end
end
