module Personalities
  class CharacterBible
    def self.compile(attributes)
      values = attributes.to_h.symbolize_keys

      <<~MARKDOWN.strip
      [Prompt text removed from public history]
      MARKDOWN
    end
  end
end
