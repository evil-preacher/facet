class UseFixedGpt4oSnapshotForConversations < ActiveRecord::Migration[8.1]
  OLD_MODEL = "gpt-4o"
  NEW_MODEL = "gpt-4o-2024-11-20"

  def up
    change_column_default :personalities, :conversation_model, from: OLD_MODEL, to: NEW_MODEL
    execute <<~SQL.squish
      UPDATE personalities
      SET conversation_model = #{connection.quote(NEW_MODEL)}
      WHERE conversation_model = #{connection.quote(OLD_MODEL)}
    SQL
  end

  def down
    change_column_default :personalities, :conversation_model, from: NEW_MODEL, to: OLD_MODEL
  end
end
