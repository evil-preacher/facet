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
      return "" if tendencies.empty?

      "Internal interaction tendencies: #{tendencies.join('; ')}. " \
        "These are not facts about the user's feelings or unspoken events. " \
        "Do not invent shared events, demand contact, or state these tendencies as facts. " \
        "Express them only when relevant and in the character's own way, within the Character Bible and user boundaries."
    end
  end
end
