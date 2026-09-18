module Personalities
  class Archive
    def self.call(personality:)
      personality.with_lock { personality.update!(status: :archived) }
      personality
    end
  end
end
