class AddInitiativeEmailDeliveries < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :initiative_email_enabled, :boolean, null: false, default: false
    remove_check_constraint :initiative_attempts, name: "initiative_attempts_decision"
    add_check_constraint :initiative_attempts,
                         "decision IS NULL OR decision IN ('NO_ACTION', 'IN_APP', 'EMAIL')",
                         name: "initiative_attempts_decision"

    create_table :initiative_email_deliveries do |t|
      t.references :initiative_attempt, null: false, index: { unique: true },
                   foreign_key: { on_delete: :cascade }
      t.string :status, null: false, default: "pending"
      t.string :email_message_id
      t.string :error_code
      t.datetime :claimed_at
      t.datetime :delivered_at
      t.timestamps
    end
    add_index :initiative_email_deliveries, :email_message_id, unique: true,
              where: "email_message_id IS NOT NULL"
    add_check_constraint :initiative_email_deliveries,
                         "status IN ('pending', 'sending', 'delivered', 'failed', 'suppressed', 'unknown')",
                         name: "initiative_email_deliveries_status"
  end
end
