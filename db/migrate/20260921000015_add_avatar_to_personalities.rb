class AddAvatarToPersonalities < ActiveRecord::Migration[8.1]
  def change
    add_column :personalities, :avatar_status, :string, null: false, default: "missing"
    add_column :personalities, :avatar_object_key, :string
    add_column :personalities, :avatar_content_type, :string
    add_column :personalities, :avatar_byte_size, :bigint
    add_column :personalities, :avatar_attempts_count, :integer, null: false, default: 0
    add_column :personalities, :avatar_started_at, :datetime
    add_column :personalities, :avatar_generated_at, :datetime
    add_column :personalities, :avatar_error_code, :string
    add_column :personalities, :avatar_error_message, :text
    add_reference :personalities, :avatar_source_version, index: true

    add_index :personalities,
              :avatar_object_key,
              unique: true,
              where: "avatar_object_key IS NOT NULL"
    add_foreign_key :personalities,
                    :personality_versions,
                    column: :avatar_source_version_id,
                    on_delete: :nullify
    add_check_constraint :personalities,
                         "avatar_status IN ('missing', 'pending', 'generating', 'ready', 'failed')",
                         name: "personalities_avatar_status"
    add_check_constraint :personalities,
                         "avatar_byte_size IS NULL OR avatar_byte_size >= 0",
                         name: "personalities_avatar_byte_size"
    add_check_constraint :personalities,
                         "avatar_attempts_count >= 0",
                         name: "personalities_avatar_attempts_count"
    add_check_constraint :personalities,
                         <<~SQL.squish,
                           avatar_status <> 'ready' OR (
                             avatar_object_key IS NOT NULL AND
                             avatar_content_type IS NOT NULL AND
                             avatar_byte_size IS NOT NULL AND
                             avatar_generated_at IS NOT NULL AND
                             avatar_source_version_id IS NOT NULL
                           )
                         SQL
                         name: "personalities_ready_avatar_metadata"
  end
end
