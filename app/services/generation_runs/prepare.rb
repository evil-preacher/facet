module GenerationRuns
  class Prepare
    Result = Data.define(:generation_run, :assistant_message)

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
      generation_run = conversation_thread.generation_runs.create!(
        personality_version: personality_version,
        user_message: user_message,
        assistant_message: assistant_message,
        idempotency_key: "generation:#{user_message.client_token}",
        status: :pending
      )

      Result.new(generation_run: generation_run, assistant_message: assistant_message)
    end
  end
end
