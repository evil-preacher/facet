module Ai
  class AvatarPrompt
    SECTION_NAMES = [ "Identity", "Base character" ].freeze

    def self.call(personality:, personality_version:)
      context = avatar_context(personality: personality, personality_version: personality_version)
      raise MissingAvatarContextError, "Character bible has no avatar sections" if context.blank?

      Ai::PromptCatalog.render("avatar_image", character_name: personality.name, character_context: context)
    end

    def self.avatar_context(personality:, personality_version:)
      versions = [ personality_version ] + personality.versions
        .where.not(id: personality_version.id)
        .order(number: :desc)

      versions.each do |version|
        context = Personalities::CharacterBibleSections.extract(version.content, names: SECTION_NAMES)
        return context if context.present?
      end

      nil
    end
    private_class_method :avatar_context
  end
end
