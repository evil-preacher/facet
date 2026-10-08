module Dynamics
  class Rollback
    def self.call(user:, personality:, source_revision:, now: Time.current)
      raise ArgumentError, "Personality belongs to another user" unless personality.user_id == user.id

      state = personality.relationship_state
      raise ArgumentError, "Revision belongs to another personality" unless state &&
        source_revision.relationship_state_id == state.id

      state.with_lock do
        emotion = personality.emotional_state || personality.create_emotional_state!
        reasons = source_revision.slow_state.each_with_object({}) do |(key, value), changes|
          previous = state.public_send(key)
          changes[key] = { "event" => "rollback", "source_revision" => source_revision.revision,
                           "delta" => value - previous } if value != previous
        end
        revision = state.dynamic_revisions.create!(
          revision: state.dynamic_revisions.maximum(:revision).to_i + 1,
          source_revision: source_revision, event_kind: "rollback",
          slow_state: source_revision.slow_state, fast_state: source_revision.fast_state,
          parameter_reasons: reasons,
          source_message_ids: [], rules_version: Rules::VERSION, effective_at: now
        )
        state.update!(source_revision.slow_state)
        emotion.update!(source_revision.fast_state.merge(observed_at: now))
        revision
      end
    end
  end
end
