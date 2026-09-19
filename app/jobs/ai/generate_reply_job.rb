module Ai
  class GenerateReplyJob < ApplicationJob
    queue_as :conversation

    discard_on ActiveJob::DeserializationError

    def perform(generation_run_id)
      generation_run = GenerationRun.find(generation_run_id)
      GenerateReply.call(generation_run: generation_run)
    end
  end
end
