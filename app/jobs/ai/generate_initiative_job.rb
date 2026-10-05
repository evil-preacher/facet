module Ai
  class GenerateInitiativeJob < ApplicationJob
    queue_as :initiative

    retry_on RetryableInitiativeError,
             wait: ->(executions) { (executions**4) + 2 },
             attempts: 4 do |_job, error|
      attempt = InitiativeAttempt.find_by(id: error.attempt_id)
      attempt&.with_lock do
        next if attempt.completed? || attempt.skipped?

        attempt.update!(status: :failed, started_at: nil, completed_at: Time.current,
                        error_code: error.error_code)
      end
    end

    def perform(attempt_id)
      attempt = InitiativeAttempt.find_by(id: attempt_id)
      Initiatives::Generate.call(attempt: attempt) if attempt
    end
  end
end
