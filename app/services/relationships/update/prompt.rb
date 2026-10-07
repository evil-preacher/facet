require "json"

class Relationships::Update::Prompt
  LANGUAGE_NAMES = { "ru" => "Russian", "en" => "English" }.freeze

  def self.call(previous_summary:, messages:, language:)
    language_name = LANGUAGE_NAMES.fetch(language)
    language_instruction = Ai::PromptCatalog.render("relationship_update_language", language_name: language_name)

    [
      { role: "developer", content: "#{Ai::PromptCatalog.content("relationship_update")}\n#{language_instruction}" },
      { role: "user", content: JSON.pretty_generate(
        previous_relationship_state: previous_summary.presence,
        conversation_turn: messages.map { |message| { id: message.id, role: message.role, content: message.content } }
      ) }
    ]
  end
end
