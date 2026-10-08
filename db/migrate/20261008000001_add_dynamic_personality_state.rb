class AddDynamicPersonalityState < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :dynamic_state_enabled, :boolean, null: false, default: false
    add_column :relationship_states, :trust, :integer, null: false, default: 50
    add_column :relationship_states, :closeness, :integer, null: false, default: 0
    add_column :relationship_states, :tension, :integer, null: false, default: 0
    %w[trust closeness tension].each do |name|
      add_check_constraint :relationship_states, "#{name} BETWEEN 0 AND 100",
                           name: "relationship_states_#{name}_range"
    end

    create_table :emotional_states do |t|
      t.references :personality, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.integer :warmth, null: false, default: 0
      t.integer :irritation, null: false, default: 0
      t.datetime :observed_at
      t.timestamps
    end
    %w[warmth irritation].each do |name|
      add_check_constraint :emotional_states, "#{name} BETWEEN 0 AND 100", name: "emotional_states_#{name}_range"
    end

    create_table :dynamic_state_observations do |t|
      t.references :personality, null: false, foreign_key: { on_delete: :cascade }
      t.references :generation_run, null: false, index: { unique: true }, foreign_key: { on_delete: :cascade }
      t.jsonb :extraction, null: false, default: {}
      t.integer :rules_version, null: false
      t.timestamps
    end
    add_check_constraint :dynamic_state_observations, "rules_version > 0",
                         name: "dynamic_state_observations_rules_version"

    create_table :dynamic_state_revisions do |t|
      t.references :relationship_state, null: false, foreign_key: { on_delete: :cascade }
      t.references :generation_run, index: { unique: true }, foreign_key: { on_delete: :nullify }
      t.references :source_revision, foreign_key: { to_table: :dynamic_state_revisions, on_delete: :nullify }
      t.integer :revision, null: false
      t.string :event_kind, null: false
      t.jsonb :extraction, null: false, default: {}
      t.jsonb :slow_state, null: false
      t.jsonb :fast_state, null: false
      t.jsonb :parameter_reasons, null: false, default: {}
      t.jsonb :source_message_ids, null: false, default: []
      t.integer :rules_version, null: false
      t.datetime :effective_at, null: false
      t.timestamps
    end
    add_index :dynamic_state_revisions, %i[relationship_state_id revision], unique: true,
              name: "index_dynamic_state_revisions_on_state_and_revision"
    add_check_constraint :dynamic_state_revisions, "revision > 0 AND rules_version > 0",
                         name: "dynamic_state_revisions_positive_versions"
  end
end
