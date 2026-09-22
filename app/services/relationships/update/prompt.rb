require "json"

class Relationships::Update::Prompt
  INSTRUCTIONS = <<~TEXT.freeze
      [Prompt text removed from public history]
  TEXT

  def self.call(previous_summary:, messages:)
    [
      { role: "developer", content: INSTRUCTIONS },
      { role: "user", content: JSON.pretty_generate(
        previous_relationship_state: previous_summary.presence,
        conversation_turn: messages.map { |message| { id: message.id, role: message.role, content: message.content } }
      ) }
    ]
  end
end
