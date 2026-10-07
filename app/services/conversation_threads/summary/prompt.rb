require "json"

module ConversationThreads
  module Summary
    class Prompt
      def self.call(previous_summary:, messages:)
        [
          { role: "developer", content: Ai::PromptCatalog.content("thread_summary") },
          { role: "user", content: JSON.pretty_generate(
            previous_summary: previous_summary.presence,
            messages: messages.map { |message| { id: message.id, role: message.role, content: message.content } }
          ) }
        ]
      end
    end
  end
end
