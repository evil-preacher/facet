module Personalities
  class DisableInitiative
    def self.call(personality:)
      personality.update!(initiative_enabled: false)
      personality
    end
  end
end
