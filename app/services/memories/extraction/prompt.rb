require "json"

module Memories
  module Extraction
    class Prompt
      def self.call(extraction:, active_memories:, now: Time.current)
        new(extraction: extraction, active_memories: active_memories, now: now).call
      end

      def self.source_messages(extraction:)
        current_message = extraction.generation_run.user_message
        extraction.generation_run.conversation_thread.messages.completed
          .where(role: :user)
          .where("position <= ?", current_message.position)
          .reorder(position: :desc)
          .limit(3)
          .to_a
          .reverse
      end

      def initialize(extraction:, active_memories:, now:)
        @extraction = extraction
        @active_memories = active_memories
        @now = now
      end

      def call
        [
          { role: "developer", content: Ai::PromptCatalog.content("memory_extraction") },
          { role: "user", content: JSON.pretty_generate(payload) }
        ]
      end

      private

      attr_reader :extraction, :active_memories, :now

      def payload
        {
          current_time: now.iso8601,
          current_message_id: extraction.generation_run.user_message.id,
          participants: {
            user_name: extraction.personality.user.profile&.first_name.presence,
            character_name: extraction.personality.name
          },
          allowed_message_ids: [ extraction.generation_run.user_message.id ],
          conversation_turn: source_messages.map do |message|
            { id: message.id, role: message.role, content: message.content }
          end,
          active_memories: active_memories.map do |memory|
            {
              id: memory.id,
              kind: memory.kind,
              content: memory.content,
              importance: memory.importance
            }
          end
        }
      end

      def source_messages
        @source_messages ||= self.class.source_messages(extraction: extraction)
      end
    end
  end
end
