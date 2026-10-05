module Ai
  class InitiativeSweepJob < ApplicationJob
    queue_as :maintenance

    def perform(now = Time.current)
      InitiativeAttempt.running.where("started_at <= ?", now - 1.hour).find_each do |attempt|
        attempt.with_lock do
          next unless attempt.running? && attempt.started_at <= now - 1.hour

          attempt.update!(status: :pending, started_at: nil)
          GenerateInitiativeJob.perform_later(attempt.id)
        end
      end
      Personality.where(status: "active", initiative_enabled: true).find_each do |personality|
        Initiatives::Schedule.call(personality: personality, now: now)
      end
    end
  end
end
