class AddInitiativeFeedbackToMessages < ActiveRecord::Migration[8.1]
  def change
    add_column :messages, :initiative_feedback, :string
    add_column :messages, :initiative_feedback_at, :datetime
    add_check_constraint :messages,
                         "initiative_feedback IS NULL OR (initiated_by = 'personality' AND initiative_feedback IN ('helpful', 'irrelevant', 'repetitive', 'unwelcome'))",
                         name: "messages_initiative_feedback_valid"
    add_check_constraint :messages,
                         "(initiative_feedback IS NULL) = (initiative_feedback_at IS NULL)",
                         name: "messages_initiative_feedback_timestamp"
  end
end
