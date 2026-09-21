class AllowAttachedUserMessagesWithoutText < ActiveRecord::Migration[8.1]
  def change
    remove_check_constraint :messages, name: "messages_content"
    add_check_constraint :messages,
                         "char_length(content) <= 100000 AND (" \
                           "status <> 'completed' OR role = 'user' OR " \
                           "char_length(btrim(content)) > 0)",
                         name: "messages_content"
  end
end
