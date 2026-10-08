module Dynamics
  class Apply
    def self.call(generation_run:, now: Time.current)
      return unless generation_run.completed? && generation_run.assistant_message&.completed?

      personality = generation_run.conversation_thread.personality
      return unless personality.dynamic_state_enabled?

      extraction = Extract.call(message: generation_run.user_message)
      state = find_or_create_state(personality)
      state.with_lock do
        return if DynamicStateObservation.exists?(generation_run: generation_run)
        return unless personality.reload.dynamic_state_enabled?

        emotion = personality.emotional_state || personality.create_emotional_state!
        slow = state.slice(:trust, :closeness, :tension).stringify_keys
        fast = emotion.slice(:warmth, :irritation).stringify_keys
        next_slow, next_fast, reasons = Rules.transition(
          slow: slow, fast: fast, observed_at: emotion.observed_at, kind: extraction.fetch("kind"), now: now
        )
        observation = personality.dynamic_state_observations.create!(
          generation_run: generation_run, extraction: extraction, rules_version: Rules::VERSION
        )
        if next_slow != slow || next_fast != fast || extraction.fetch("kind") != "none"
          revision = state.dynamic_revisions.create!(
            generation_run: generation_run, revision: state.dynamic_revisions.maximum(:revision).to_i + 1,
            event_kind: extraction.fetch("kind"), extraction: extraction,
            slow_state: next_slow, fast_state: next_fast, parameter_reasons: reasons,
            source_message_ids: extraction.fetch("source_message_ids"),
            rules_version: Rules::VERSION, effective_at: now
          )
          state.update!(next_slow)
          emotion.update!(next_fast.merge(observed_at: now))
          revision
        else
          observation
        end
      end
    end

    def self.find_or_create_state(personality)
      personality.relationship_state || personality.create_relationship_state!
    rescue ActiveRecord::RecordNotUnique
      personality.reload.relationship_state
    end
    private_class_method :find_or_create_state
  end
end
