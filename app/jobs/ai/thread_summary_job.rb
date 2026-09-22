module Ai
  class ThreadSummaryJob < ApplicationJob
    queue_as :memory
    discard_on ActiveJob::DeserializationError
    retry_on RetryableContextUpdateError, wait: ->(executions) { (executions**4) + 2 }, attempts: 5

    def perform(generation_run_id)
      ConversationThreads::Summarize.call(generation_run: GenerationRun.find(generation_run_id))
    end
  end
end
