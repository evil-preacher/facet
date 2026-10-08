class AddAutonomousInitiativePolicy < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :initiative_intensity, :string, null: false, default: "quiet"
    add_column :personalities, :initiative_timezone, :string, null: false, default: "UTC"
    add_column :personalities, :initiative_quiet_start_hour, :integer, null: false, default: 22
    add_column :personalities, :initiative_quiet_end_hour, :integer, null: false, default: 8
    add_check_constraint :personalities, "initiative_intensity IN ('quiet', 'normal', 'expressive')",
                         name: "personalities_initiative_intensity"
    add_check_constraint :personalities,
                         "(initiative_quiet_start_hour BETWEEN 0 AND 23 AND initiative_quiet_end_hour BETWEEN 0 AND 23 " \
                         "AND initiative_quiet_start_hour <> initiative_quiet_end_hour)",
                         name: "personalities_initiative_quiet_hours"

    add_column :initiative_attempts, :decision, :string
    add_column :initiative_attempts, :motivation, :string
    add_column :initiative_attempts, :intensity, :string
    add_column :initiative_attempts, :decision_reason, :string
    add_column :initiative_attempts, :decided_at, :datetime
    add_reference :initiative_attempts, :dynamic_state_revision,
                  foreign_key: { on_delete: :nullify }
    add_check_constraint :initiative_attempts, "decision IS NULL OR decision IN ('NO_ACTION', 'IN_APP')",
                         name: "initiative_attempts_decision"
    add_check_constraint :initiative_attempts,
                         "intensity IS NULL OR intensity IN ('low', 'medium', 'high')",
                         name: "initiative_attempts_intensity"
  end
end
