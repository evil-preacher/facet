module GenerationRuns
  class Prepare
    Result = Data.define(:generation_run, :assistant_message, :outbox_event)

    def self.call(conversation_thread:, user_message:)
      personality_version = user_message.personality_version
      assistant_message = conversation_thread.messages.create!(
        personality_version: personality_version,
        position: user_message.position + 1,
        role: :assistant,
        status: :streaming,
        language: "und",
        content: "",
        client_token: nil
      )
      personality = conversation_thread.personality
      if personality.avatar_ready? && Messages::PhotoRequestDetector.call(user_message.content)
        assistant_message.create_message_image!(
          source_avatar_object_key: personality.avatar_object_key
        )
      end
      generation_run = conversation_thread.generation_runs.create!(
        personality_version: personality_version,
        user_message: user_message,
        assistant_message: assistant_message,
        idempotency_key: "generation:#{user_message.client_token}",
        status: :pending
      )
      outbox_event = Outbox::Publish.call(
        event_key: "generate-reply:#{generation_run.id}",
        job_class: Ai::GenerateReplyJob,
        arguments: [ generation_run.id ]
      )

      Result.new(
        generation_run: generation_run,
        assistant_message: assistant_message,
        outbox_event: outbox_event
      )
    end
  end
end
