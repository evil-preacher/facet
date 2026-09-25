module Ai
  class RelationshipConsolidationJob < ApplicationJob
    queue_as :memory
    discard_on ActiveJob::DeserializationError
    retry_on RetryableContextUpdateError, wait: ->(executions) { (executions**4) + 2 }, attempts: 5

    RETRYABLE_OUTPUT_ERRORS = %w[invalid_output invalid_scope_check scope_violation].freeze

    def perform(generation_run_id)
      result = Relationships::Consolidate.call(generation_run: GenerationRun.find(generation_run_id))
      return unless RETRYABLE_OUTPUT_ERRORS.include?(result.error_code)

      raise RetryableContextUpdateError.new(
        generation_run_id: generation_run_id, error_code: result.error_code
      )
    end
  end
end
