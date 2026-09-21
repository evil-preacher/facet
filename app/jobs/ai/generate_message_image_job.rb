module Ai
  class GenerateMessageImageJob < ApplicationJob
    MAX_ATTEMPTS = 5

    queue_as :avatar

    discard_on ActiveJob::DeserializationError
    retry_on RetryableMessageImageError,
             wait: ->(executions) { (executions**4) + 2 },
             attempts: MAX_ATTEMPTS do |_job, error|
      GenerateMessageImage.mark_terminal!(
        message_image_id: error.message_image_id,
        error_code: error.error_code
      )
    end

    def perform(message_image_id)
      message_image = MessageImage.find(message_image_id)
      GenerateMessageImage.call(message_image: message_image)
    end
  end
end
