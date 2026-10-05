class AddAiSpendingBudgets < ActiveRecord::Migration[8.1]
  def change
    add_column :users, :monthly_ai_limit_microusd, :bigint, default: 20_000_000, null: false
    add_check_constraint :users, "monthly_ai_limit_microusd >= 0", name: "users_nonnegative_ai_limit"

    add_column :model_calls, :reserved_cost_microusd, :bigint, default: 0, null: false
    add_column :model_calls, :reservation_expires_at, :datetime
    add_check_constraint :model_calls, "reserved_cost_microusd >= 0", name: "model_calls_nonnegative_reservation"
    add_index :model_calls, :reservation_expires_at, where: "status = 'pending' AND reserved_cost_microusd > 0"

    create_table :ai_budget_locks do |t|
      t.timestamps
    end
  end
end
