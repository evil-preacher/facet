module GenerationRuns
  class Retry
    include ActiveModel::Model

    attr_accessor :generation_run

    def self.call(generation_run:)
      new(generation_run: generation_run).call
    end

    def call
      generation_run.with_lock do
        unless retryable?
          errors.add(:generation_run, :invalid)
          return self
        end

        generation_run.update!(
          status: :pending,
          error_code: nil,
          error_message: nil,
          started_at: nil,
          completed_at: nil
        )
      end

      self
    end

    def retryable?
      (generation_run.failed? || generation_run.stopped?) &&
        generation_run.conversation_thread.active? &&
        generation_run.conversation_thread.personality.active?
    end

    def success?
      errors.empty? && generation_run.pending?
    end
  end
end
