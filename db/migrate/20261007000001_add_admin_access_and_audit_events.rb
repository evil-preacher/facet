class AddAdminAccessAndAuditEvents < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :admin, :boolean, default: false, null: false

    create_table :admin_audit_events do |t|
      t.bigint :actor_user_id, null: false
      t.string :action, null: false
      t.string :target_type, null: false
      t.bigint :target_id
      t.datetime :created_at, null: false
    end

    add_index :admin_audit_events, [ :actor_user_id, :created_at ]
    add_index :admin_audit_events, [ :target_type, :target_id, :created_at ]
    add_check_constraint :admin_audit_events,
                         "action IN ('index', 'show', 'disable_initiative', 'retry_pending')",
                         name: "admin_audit_events_action"
  end
end
