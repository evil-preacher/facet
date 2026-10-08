module Dynamics
  class Reset
    def self.call(user:, personality:, now: Time.current)
      raise ArgumentError, "Personality belongs to another user" unless personality.user_id == user.id

      state = personality.relationship_state || personality.create_relationship_state!
      state.with_lock do
        emotion = personality.emotional_state || personality.create_emotional_state!
        reasons = Rules::BASE_SLOW.each_with_object({}) do |(key, value), changes|
          previous = state.public_send(key)
          changes[key] = { "event" => "user_reset", "delta" => value - previous } if value != previous
        end
        revision = state.dynamic_revisions.create!(
          revision: state.dynamic_revisions.maximum(:revision).to_i + 1,
          event_kind: "reset", slow_state: Rules::BASE_SLOW, fast_state: Rules::BASE_FAST,
          parameter_reasons: reasons,
          source_message_ids: [], rules_version: Rules::VERSION, effective_at: now
        )
        state.update!(Rules::BASE_SLOW)
        emotion.update!(Rules::BASE_FAST.merge(observed_at: now))
        revision
      end
    end
  end
end
