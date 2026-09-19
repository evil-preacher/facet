class SwitchDefaultAiProviderToMistral < ActiveRecord::Migration[8.1]
  OPENAI_CONVERSATION_MODEL = "gpt-4o-2024-11-20"
  OPENAI_UTILITY_MODEL = "gpt-4o-mini"
  MISTRAL_CONVERSATION_MODEL = "mistral-large-2512"
  MISTRAL_UTILITY_MODEL = "mistral-small-latest"

  def up
    change_column_default :personalities, :conversation_model,
      from: OPENAI_CONVERSATION_MODEL, to: MISTRAL_CONVERSATION_MODEL
    change_column_default :personalities, :utility_model,
      from: OPENAI_UTILITY_MODEL, to: MISTRAL_UTILITY_MODEL

    replace_model(OPENAI_CONVERSATION_MODEL, MISTRAL_CONVERSATION_MODEL, :conversation_model)
    replace_model(OPENAI_UTILITY_MODEL, MISTRAL_UTILITY_MODEL, :utility_model)
  end

  def down
    change_column_default :personalities, :conversation_model,
      from: MISTRAL_CONVERSATION_MODEL, to: OPENAI_CONVERSATION_MODEL
    change_column_default :personalities, :utility_model,
      from: MISTRAL_UTILITY_MODEL, to: OPENAI_UTILITY_MODEL

    replace_model(MISTRAL_CONVERSATION_MODEL, OPENAI_CONVERSATION_MODEL, :conversation_model)
    replace_model(MISTRAL_UTILITY_MODEL, OPENAI_UTILITY_MODEL, :utility_model)
  end

  private

  def replace_model(old_model, new_model, column)
    execute <<~SQL.squish
      UPDATE personalities
      SET #{column} = #{connection.quote(new_model)}
      WHERE #{column} = #{connection.quote(old_model)}
    SQL
  end
end
