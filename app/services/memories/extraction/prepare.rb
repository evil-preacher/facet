module Memories
  module Extraction
    class Prepare
      def self.call(generation_run:)
        personality = generation_run.conversation_thread.personality
        return unless personality.automatic_memory_enabled?
        return unless generation_run.completed? && generation_run.assistant_message&.completed?

        extraction = MemoryExtraction.create_or_find_by!(generation_run: generation_run) do |record|
          record.personality = personality
        end
        event = Outbox::Publish.call(
          event_key: "memory-extraction:#{extraction.id}",
          job_class: Ai::MemoryExtractionJob,
          arguments: [ extraction.id ]
        )
        [ extraction, event ]
      end
    end
  end
end
