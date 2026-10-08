module Personalities
  class Destroy
    def self.call(user:, personality:)
      raise ActiveRecord::RecordNotFound unless personality.user_id == user.id

      new(personality).call
    end

    def initialize(personality)
      @personality = personality
    end

    def call
      Personality.transaction do
        @personality.lock!
        keys = object_keys
        discard_pending_events
        @personality.initiative_attempts.delete_all
        @personality.memory_extractions.delete_all
        @personality.memories.delete_all
        @personality.relationship_state&.versions&.delete_all
        @personality.relationship_state&.delete
        @personality.model_calls.update_all(generation_run_id: nil, personality_id: nil)

        @personality.conversation_threads.each do |thread|
          thread.summary_versions.delete_all
          thread.generation_runs.update_all(retry_of_id: nil)
          thread.generation_runs.delete_all
          thread.messages.delete_all
          thread.delete
        end

        @personality.update_columns(status: "archived", avatar_status: "missing",
                                    current_version_id: nil, avatar_source_version_id: nil)
        @personality.versions.delete_all
        @personality.delete

        keys.each do |key|
          Outbox::Publish.call(
            event_key: "object-delete-#{Digest::SHA256.hexdigest(key)}",
            job_class: ObjectStorage::DeleteObjectJob,
            arguments: [ key ]
          )
        end
      end
    end

    private

    def object_keys
      keys = [ @personality.avatar_object_key ]
      MessageAttachment.joins(message: :conversation_thread)
        .where(conversation_threads: { personality_id: @personality.id }).pluck(:object_key).each { |key| keys << key }
      MessageImage.joins(message: :conversation_thread)
        .where(conversation_threads: { personality_id: @personality.id }).pluck(:object_key).each { |key| keys << key }
      keys.compact.uniq
    end

    def discard_pending_events
      run_ids = @personality.conversation_threads.joins(:generation_runs)
        .pluck("generation_runs.id")
      extraction_ids = @personality.memory_extractions.pluck(:id)
      attempt_ids = @personality.initiative_attempts.pluck(:id)
      image_ids = MessageImage.joins(message: :conversation_thread)
        .where(conversation_threads: { personality_id: @personality.id }).pluck(:id)
      event_keys = run_ids.flat_map do |id|
        %w[generate-reply relationship-update thread-summary relationship-consolidation dynamic-state-update].map { |kind| "#{kind}:#{id}" }
      end
      event_keys.concat(extraction_ids.map { |id| "memory-extraction:#{id}" })
      event_keys.concat(attempt_ids.map { |id| "generate-initiative:#{id}" })
      event_keys.concat(attempt_ids.map { |id| "deliver-initiative-email:#{id}" })
      event_keys.concat(image_ids.map { |id| "generate-message-image:#{id}" })
      OutboxEvent.where(event_key: event_keys).delete_all if event_keys.any?
      OutboxEvent.where("event_key LIKE ?", "generate-avatar:#{@personality.id}:%").delete_all
    end
  end
end
