module Ai
  module Initiatives
    class Policy
      LIMITS = {
        "quiet" => [ 1, 2 ],
        "normal" => [ 1, 3 ],
        "expressive" => [ 2, 5 ]
      }.freeze

      def self.call(personality:, now: Time.current, motivation: nil, intensity: nil, channel: nil)
        return "disabled" unless personality.active? && personality.initiative_enabled?
        return "quiet_hours" if quiet_hours?(personality, now)
        if channel == "EMAIL"
          block = email_delivery_block(personality: personality, now: now)
          return block if block
        end

        attempts = personality.initiative_attempts.completed
        daily_limit, weekly_limit = LIMITS.fetch(personality.initiative_intensity)
        return "daily_limit" if attempts.where(completed_at: (now - 1.day)..now).count >= daily_limit
        return "weekly_limit" if attempts.where(completed_at: (now - 7.days)..now).count >= weekly_limit

        latest = attempts.order(completed_at: :desc, id: :desc).first
        if latest&.message
          replied = Message.joins(:conversation_thread)
            .where(role: "user", conversation_threads: { personality_id: personality.id })
            .where("messages.created_at > ?", latest.message.created_at).exists?
          return "unanswered" unless replied
        end

        if motivation.present?
          repeated = attempts.where(completed_at: (now - 7.days)..now).where.not(motivation: nil)
            .pluck(:motivation).any? { |previous| previous.strip.casecmp?(motivation.strip) }
          return "repeated_motivation" if repeated
        end

        return unless intensity

        return "intensity_limit" if intensity == "medium" && personality.initiative_intensity == "quiet"
        if intensity == "high"
          state = personality.relationship_state
          return "intensity_limit" unless personality.initiative_intensity == "expressive" &&
            state && state.trust >= 70 && state.tension <= 10
        end
        nil
      end

      def self.email_delivery_block(personality:, now: Time.current)
        return "email_disabled" unless personality.active? && personality.initiative_enabled? &&
          personality.initiative_email_enabled? && personality.user.confirmed?
        return "quiet_hours" if quiet_hours?(personality, now)

        nil
      end

      def self.quiet_hours?(personality, now)
        zone = ActiveSupport::TimeZone[personality.initiative_timezone]
        return true unless zone

        hour = now.in_time_zone(zone).hour
        start_hour = personality.initiative_quiet_start_hour
        end_hour = personality.initiative_quiet_end_hour
        if start_hour < end_hour
          hour >= start_hour && hour < end_hour
        else
          hour >= start_hour || hour < end_hour
        end
      end
      private_class_method :quiet_hours?
    end
  end
end
