module Ai
  class LanguageDetector
    CYRILLIC = /\p{Cyrillic}/
    LATIN = /\p{Latin}/

    def self.call(text)
      characters = text.to_s.each_char
      cyrillic_count = characters.count { |character| character.match?(CYRILLIC) }
      latin_count = text.to_s.each_char.count { |character| character.match?(LATIN) }

      return "und" if cyrillic_count.zero? && latin_count.zero?

      cyrillic_count >= latin_count ? "ru" : "en"
    end
  end
end
