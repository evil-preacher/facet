module Ai
  class MemoryExtractionJob < ApplicationJob
    MAX_ATTEMPTS = 5

    queue_as :memory

    discard_on ActiveJob::DeserializationError
    retry_on RetryableMemoryExtractionError,
             wait: ->(executions) { (executions**4) + 2 },
             attempts: MAX_ATTEMPTS do |_job, error|
      Memories::Extract.mark_terminal!(
        memory_extraction_id: error.memory_extraction_id,
        error_code: error.error_code
      )
    end

    def perform(memory_extraction_id)
      extraction = MemoryExtraction.find(memory_extraction_id)
      Memories::Extract.call(extraction: extraction)
    end
  end
end
