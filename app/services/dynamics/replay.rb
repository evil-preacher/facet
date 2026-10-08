module Dynamics
  class Replay
    Result = Data.define(:slow_state, :fast_state, :mismatched_revisions) do
      def consistent? = mismatched_revisions.empty?
    end

    def self.call(relationship_state:)
      slow = Rules::BASE_SLOW.dup
      fast = Rules::BASE_FAST.dup
      observed_at = nil
      snapshots = {}
      mismatches = []

      relationship_state.dynamic_revisions.each do |revision|
        case revision.event_kind
        when "reset"
          slow, fast = Rules::BASE_SLOW.dup, Rules::BASE_FAST.dup
        when "rollback"
          source = snapshots.fetch(revision.source_revision_id)
          slow, fast = source.map(&:dup)
        when "time_decay"
          slow, fast, = Rules.transition(
            slow: slow, fast: fast, observed_at: observed_at, kind: "none", now: revision.effective_at,
            version: revision.rules_version
          )
        else
          slow, fast, = Rules.transition(
            slow: slow, fast: fast, observed_at: observed_at,
            kind: revision.event_kind, now: revision.effective_at, version: revision.rules_version
          )
        end
        mismatches << revision.revision unless revision.slow_state == slow && revision.fast_state == fast
        snapshots[revision.id] = [ slow.dup, fast.dup ]
        observed_at = revision.effective_at
      end
      actual_slow = relationship_state.reload.slice(:trust, :closeness, :tension).stringify_keys
      actual_fast = EmotionalState.find_by(personality_id: relationship_state.personality_id)
        &.slice(:warmth, :irritation)&.stringify_keys || Rules::BASE_FAST
      mismatches << "current" unless actual_slow == slow && actual_fast == fast
      Result.new(slow_state: slow, fast_state: fast, mismatched_revisions: mismatches)
    end
  end
end
