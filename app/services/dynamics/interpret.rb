module Dynamics
  class Interpret
    def self.call(relationship_state:, emotional_state:, now: Time.current)
      return "" unless relationship_state && emotional_state

      _, fast, = Rules.transition(
        slow: relationship_state.slice(:trust, :closeness, :tension),
        fast: emotional_state.slice(:warmth, :irritation),
        observed_at: emotional_state.observed_at, kind: "none", now: now
      )
      tendencies = []
      tendencies << "trust has grown" if relationship_state.trust >= 60
      tendencies << "trust is fragile" if relationship_state.trust <= 40
      tendencies << "familiarity has grown" if relationship_state.closeness >= 10
      tendencies << "some friction remains" if relationship_state.tension >= 8
      tendencies << "warmth is present" if fast.fetch("warmth") >= 10
      tendencies << "irritation is present" if fast.fetch("irritation") >= 10
      recent_events = relationship_state.dynamic_revisions
        .where(event_kind: %w[jealousy attraction boundary space_request])
        .where(effective_at: (now - 7.days)..now)
        .reorder(effective_at: :desc, id: :desc).limit(2).pluck(:event_kind).uniq
      recent_events = [] if %w[boundary space_request].include?(recent_events.first)
      grounded_context = recent_events.filter_map do |event|
        case event
        when "jealousy" then "the user explicitly mentioned feeling jealous"
        when "attraction" then "the user explicitly mentioned attraction"
        end
      end
      return "" if tendencies.empty? && grounded_context.empty?

      "Internal interaction tendencies: #{(tendencies + grounded_context).join('; ')}. " \
        "These are not facts about the user's feelings or unspoken events. " \
        "Do not invent shared events, demand contact, or state these tendencies as facts. " \
        "Express them only when relevant and in the character's own way, within the Character Bible and user boundaries."
    end
  end
end
