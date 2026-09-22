require "json"

module Memories
  module Extraction
    class Prompt
      INSTRUCTIONS = <<~PROMPT.freeze
      [Prompt text removed from public history]
      PROMPT

      def self.call(extraction:, active_memories:, now: Time.current)
        new(extraction: extraction, active_memories: active_memories, now: now).call
      end

      def initialize(extraction:, active_memories:, now:)
        @extraction = extraction
        @active_memories = active_memories
        @now = now
      end

      def call
        [
          { role: "developer", content: INSTRUCTIONS },
          { role: "user", content: JSON.pretty_generate(payload) }
        ]
      end

      private

      attr_reader :extraction, :active_memories, :now

      def payload
        {
          current_time: now.iso8601,
          allowed_message_ids: source_messages.map(&:id),
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
        @source_messages ||= [
          extraction.generation_run.user_message,
          extraction.generation_run.assistant_message
        ].compact
      end
    end
  end
end
