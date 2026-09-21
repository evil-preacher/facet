module Ai
  class AvatarPrompt
    SECTION_NAMES = [ "Identity", "Base character" ].freeze

    def self.call(personality:, personality_version:)
      context = Personalities::CharacterBibleSections.extract(
        personality_version.content,
        names: SECTION_NAMES
      )
      raise MissingAvatarContextError, "Character bible has no avatar sections" if context.blank?

      <<~PROMPT.strip
      [Prompt text removed from public history]
      PROMPT
    end
  end
end
