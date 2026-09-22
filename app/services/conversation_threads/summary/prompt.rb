require "json"

module ConversationThreads
  module Summary
    class Prompt
      INSTRUCTIONS = <<~TEXT.freeze
      [Prompt text removed from public history]
      TEXT

      def self.call(previous_summary:, messages:)
        [
          { role: "developer", content: INSTRUCTIONS },
          { role: "user", content: JSON.pretty_generate(
            previous_summary: previous_summary.presence,
            messages: messages.map { |message| { id: message.id, role: message.role, content: message.content } }
          ) }
        ]
      end
    end
  end
end
