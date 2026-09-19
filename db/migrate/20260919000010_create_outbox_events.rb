class CreateOutboxEvents < ActiveRecord::Migration[8.1]
  def change
    create_table :outbox_events do |t|
      t.string :event_key, null: false
      t.string :job_class, null: false
      t.string :queue_name, null: false
      t.jsonb :arguments, null: false, default: []
      t.string :status, null: false, default: "pending"
      t.integer :attempts_count, null: false, default: 0
      t.datetime :available_at, null: false
      t.datetime :locked_at
      t.datetime :dispatched_at
      t.text :last_error
      t.timestamps

      t.index :event_key, unique: true
      t.index [ :status, :available_at ], name: "index_outbox_events_for_dispatch"
      t.check_constraint "status IN ('pending', 'processing', 'dispatched')",
                         name: "outbox_events_status"
      t.check_constraint "attempts_count >= 0", name: "outbox_events_attempts_count"
      t.check_constraint "jsonb_typeof(arguments) = 'array'", name: "outbox_events_arguments_array"
    end
  end
end
