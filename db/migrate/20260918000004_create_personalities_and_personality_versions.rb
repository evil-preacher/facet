class CreatePersonalitiesAndPersonalityVersions < ActiveRecord::Migration[8.1]
  def change
    create_table :personalities do |t|
      t.references :user, null: false, foreign_key: true
      t.string :name, null: false
      t.text :description, null: false, default: ""
      t.string :status, null: false, default: "draft"
      t.bigint :current_version_id

      t.timestamps
    end

    add_index :personalities, %i[user_id status]
    add_index :personalities, :current_version_id, unique: true
    add_check_constraint :personalities,
                         "char_length(btrim(name)) BETWEEN 1 AND 80",
                         name: "personalities_name_length"
    add_check_constraint :personalities,
                         "char_length(description) <= 500",
                         name: "personalities_description_length"
    add_check_constraint :personalities,
                         "status IN ('draft', 'active', 'archived')",
                         name: "personalities_status"

    create_table :personality_versions do |t|
      t.references :personality, null: false, foreign_key: true
      t.integer :number, null: false
      t.text :content, null: false
      t.text :change_note
      t.bigint :source_version_id

      t.timestamps
    end

    add_index :personality_versions, %i[personality_id number], unique: true
    add_index :personality_versions, :source_version_id
    add_check_constraint :personality_versions,
                         "number > 0",
                         name: "personality_versions_positive_number"
    add_check_constraint :personality_versions,
                         "char_length(btrim(content)) BETWEEN 1 AND 20000",
                         name: "personality_versions_content_length"
    add_foreign_key :personality_versions,
                    :personality_versions,
                    column: :source_version_id,
                    on_delete: :nullify
    add_foreign_key :personalities,
                    :personality_versions,
                    column: :current_version_id,
                    on_delete: :nullify
  end
end
