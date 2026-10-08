module Dynamics
  class Advance
    def self.call(personality:, now: Time.current)
      return unless personality.dynamic_state_enabled?

      state = personality.relationship_state
      emotion = personality.emotional_state
      return unless state && emotion && emotion.observed_at && now > emotion.observed_at

      state.with_lock do
        return unless personality.reload.dynamic_state_enabled?

        emotion.reload
        slow = state.slice(:trust, :closeness, :tension).stringify_keys
        fast = emotion.slice(:warmth, :irritation).stringify_keys
        _, next_fast, = Rules.transition(
          slow: slow, fast: fast, observed_at: emotion.observed_at, kind: "none", now: now
        )
        return if next_fast == fast

        revision = state.dynamic_revisions.create!(
          revision: state.dynamic_revisions.maximum(:revision).to_i + 1,
          event_kind: "time_decay", slow_state: slow, fast_state: next_fast,
          parameter_reasons: fast.keys.index_with { |key| { "event" => "time_decay" } if next_fast[key] != fast[key] }.compact,
          source_message_ids: [], rules_version: Rules::VERSION, effective_at: now
        )
        emotion.update!(next_fast.merge(observed_at: now))
        revision
      end
    end
  end
end
