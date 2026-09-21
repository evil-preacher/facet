module Ai
  class GenerateReplyJob < ApplicationJob
    TRANSIENT_ERROR_CODES = %w[timeout rate_limit provider_error].freeze
    MAX_ATTEMPTS = 5

    queue_as :conversation

    discard_on ActiveJob::DeserializationError
    retry_on RetryableGenerationError,
             wait: ->(executions) { (executions**4) + 2 },
             attempts: MAX_ATTEMPTS do |job, error|
      job.send(:mark_terminal!, error)
    end

    def perform(generation_run_id)
      generation_run = GenerationRun.find(generation_run_id)
      result = GenerateReply.call(generation_run: generation_run)
      schedule_retry!(generation_run, result.error_code) if TRANSIENT_ERROR_CODES.include?(result.error_code)
    rescue RetryableGenerationError
      raise
    rescue StandardError => error
      mark_unexpected_failure!(generation_run, error) if generation_run
      raise
    end

    private

    def schedule_retry!(generation_run, error_code)
      generation_run.with_lock do
        return unless generation_run.failed?

        generation_run.update!(status: :pending, completed_at: nil)
        generation_run.assistant_message&.update!(status: :streaming)
      end
      raise RetryableGenerationError.new(
        generation_run_id: generation_run.id,
        error_code: error_code
      )
    end

    def mark_terminal!(error)
      generation_run = GenerationRun.find_by(id: error.generation_run_id)
      return unless generation_run

      generation_run.with_lock do
        return if generation_run.completed? || generation_run.stopped?

        generation_run.update!(
          status: :failed,
          error_code: error.error_code,
          error_message: "Model provider request failed after retries",
          completed_at: Time.current
        )
        generation_run.assistant_message&.update!(status: :failed)
        generation_run.assistant_message&.message_image&.mark_failed!(error_code: error.error_code)
      end
    end

    def mark_unexpected_failure!(generation_run, error)
      generation_run.with_lock do
        return if generation_run.completed? || generation_run.stopped?

        generation_run.update!(
          status: :failed,
          error_code: "unexpected_error",
          error_message: error.class.name,
          completed_at: Time.current
        )
        generation_run.assistant_message&.update!(status: :failed)
        generation_run.assistant_message&.message_image&.mark_failed!(error_code: "unexpected_error")
      end
    rescue ActiveRecord::ActiveRecordError
      nil
    end
  end
end
