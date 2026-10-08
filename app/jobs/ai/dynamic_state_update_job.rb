module Ai
  class DynamicStateUpdateJob < ApplicationJob
    queue_as :memory
    discard_on ActiveJob::DeserializationError

    def perform(generation_run_id)
      run = GenerationRun.find_by(id: generation_run_id)
      Dynamics::Apply.call(generation_run: run) if run
    end
  end
end
