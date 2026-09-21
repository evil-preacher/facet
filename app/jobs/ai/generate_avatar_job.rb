module Ai
  class GenerateAvatarJob < ApplicationJob
    MAX_ATTEMPTS = 5

    queue_as :avatar

    discard_on ActiveJob::DeserializationError
    retry_on RetryableAvatarError,
             wait: ->(executions) { (executions**4) + 2 },
             attempts: MAX_ATTEMPTS do |_job, error|
      GenerateAvatar.mark_terminal!(
        personality_id: error.personality_id,
        personality_version_id: error.personality_version_id,
        error_code: error.error_code
      )
    end

    def perform(personality_id, personality_version_id)
      personality = Personality.find(personality_id)
      personality_version = personality.versions.find(personality_version_id)
      GenerateAvatar.call(
        personality: personality,
        personality_version: personality_version
      )
    end
  end
end
