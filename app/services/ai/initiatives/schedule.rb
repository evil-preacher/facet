module Ai
  module Initiatives
    class Schedule
      def self.call(personality:, now: Time.current)
        personality.with_lock do
          eligibility = Eligibility.call(personality: personality, now: now)
          next unless eligibility.eligible

          attempt = personality.initiative_attempts.create!(
            conversation_thread: eligibility.thread,
            personality_version: personality.current_version,
            source_message: eligibility.last_user_message,
            ai_provider: Rails.configuration.x.ai.provider,
            status: :pending, created_at: now
          )
          Outbox::Publish.call(
            event_key: "generate-initiative:#{attempt.id}",
            job_class: GenerateInitiativeJob,
            arguments: [ attempt.id ]
          )
          attempt
        end
      end
    end
  end
end
