module ConversationThreads
  class Title
    MAX_LENGTH = 80

    def self.from(content)
      normalized = content.to_s.squish
      return normalized if normalized.length <= MAX_LENGTH

      "#{normalized.first(MAX_LENGTH - 1).rstrip}…"
    end
  end
end
