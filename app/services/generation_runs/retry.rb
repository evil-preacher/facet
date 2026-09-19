module GenerationRuns
  class Retry
    include ActiveModel::Model

    attr_reader :source_generation_run, :generation_run

    def self.call(generation_run:)
      new(generation_run: generation_run).call
    end

    def initialize(generation_run:)
      @source_generation_run = generation_run
      @created = false
    end

    def call
      source_generation_run.with_lock do
        @generation_run = source_generation_run.retry_run
        return self if generation_run

        unless retryable?
          errors.add(:generation_run, :invalid)
          return self
        end

        assistant_message = source_generation_run.conversation_thread.messages.create!(
          personality_version: source_generation_run.personality_version,
          position: source_generation_run.conversation_thread.messages.maximum(:position).to_i + 1,
          role: :assistant,
          status: :streaming,
          language: "und",
          content: "",
          client_token: nil
        )
        @generation_run = source_generation_run.conversation_thread.generation_runs.create!(
          personality_version: source_generation_run.personality_version,
          user_message: source_generation_run.user_message,
          assistant_message: assistant_message,
          retry_of: source_generation_run,
          idempotency_key: "retry:#{source_generation_run.id}",
          status: :pending
        )
        @created = true
      end
      Ai::GenerateReplyJob.perform_later(generation_run.id) if @created

      self
    rescue ActiveRecord::RecordNotUnique
      @generation_run = source_generation_run.reload.retry_run
      self
    end

    def retryable?
      (source_generation_run.failed? || source_generation_run.stopped?) &&
        source_generation_run.conversation_thread.active? &&
        source_generation_run.conversation_thread.personality.active?
    end

    def success?
      errors.empty? && generation_run.pending?
    end
  end
end
