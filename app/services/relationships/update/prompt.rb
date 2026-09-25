require "json"

class Relationships::Update::Prompt
  INSTRUCTIONS = <<~TEXT.freeze
      [Prompt text removed from public history]
  TEXT

  LANGUAGE_NAMES = { "ru" => "Russian", "en" => "English" }.freeze

  def self.call(previous_summary:, messages:, language:)
    language_name = LANGUAGE_NAMES.fetch(language)
    language_instruction = <<~TEXT.strip
      [Prompt text removed from public history]
    TEXT

    [
      { role: "developer", content: "#{INSTRUCTIONS}\n#{language_instruction}" },
      { role: "user", content: JSON.pretty_generate(
        previous_relationship_state: previous_summary.presence,
        conversation_turn: messages.map { |message| { id: message.id, role: message.role, content: message.content } }
      ) }
    ]
  end
end
