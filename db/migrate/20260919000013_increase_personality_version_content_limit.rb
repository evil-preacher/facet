class IncreasePersonalityVersionContentLimit < ActiveRecord::Migration[8.1]
  def up
    remove_check_constraint :personality_versions, name: "personality_versions_content_length"
    add_check_constraint :personality_versions,
                         "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 50000",
                         name: "personality_versions_content_length"
  end

  def down
    remove_check_constraint :personality_versions, name: "personality_versions_content_length"
    add_check_constraint :personality_versions,
                         "char_length(btrim(content)) >= 1 AND char_length(btrim(content)) <= 20000",
                         name: "personality_versions_content_length"
  end
end
