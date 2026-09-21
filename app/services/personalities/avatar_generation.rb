module Personalities
  module AvatarGeneration
    def self.enqueue(personality:, personality_version:)
      result = Prepare.call(
        personality: personality,
        personality_version: personality_version
      )
      if result.outbox_event
        Outbox::Dispatcher.call(limit: 1, event_ids: [ result.outbox_event.id ])
      end
      result
    end

    def self.enqueue_safely(personality:, personality_version:)
      enqueue(personality: personality, personality_version: personality_version)
    rescue StandardError => error
      Rails.logger.error(
        "Could not schedule avatar generation personality_id=#{personality.id} " \
        "version_id=#{personality_version.id} error=#{error.class.name}"
      )
      Prepare::Result.new(outbox_event: nil)
    end
  end
end
