require "json"

class Relationships::Consolidate::Prompt
  INSTRUCTIONS = <<~TEXT.freeze
      [Prompt text removed from public history]
  TEXT

  def self.call(previous_summary:, messages:, complete_evidence:, language:)
    language_name = Relationships::Update::Prompt::LANGUAGE_NAMES.fetch(language)
    instructions = INSTRUCTIONS
    [
      { role: "developer", content: instructions },
      { role: "user", content: JSON.pretty_generate(
        previous_relationship_state: previous_summary,
        complete_evidence: complete_evidence,
        evidence_messages: messages.map do |message|
          { id: message.id, thread_id: message.conversation_thread_id, role: message.role, content: message.content }
        end
      ) }
    ]
  end
end
