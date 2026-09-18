class AddAuthorToPersonalityVersions < ActiveRecord::Migration[8.1]
  def up
    add_reference :personality_versions,
                  :author,
                  null: true,
                  foreign_key: { to_table: :users }

    execute <<~SQL.squish
      UPDATE personality_versions
      SET author_id = personalities.user_id
      FROM personalities
      WHERE personality_versions.personality_id = personalities.id
    SQL

    change_column_null :personality_versions, :author_id, false
    add_check_constraint :personality_versions,
                         "change_note IS NULL OR char_length(change_note) <= 500",
                         name: "personality_versions_change_note_length"
  end

  def down
    remove_check_constraint :personality_versions,
                            name: "personality_versions_change_note_length"
    remove_reference :personality_versions, :author, foreign_key: { to_table: :users }
  end
end
