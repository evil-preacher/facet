module Personalities
  class CharacterBible
    def self.compile(attributes)
      values = attributes.to_h.symbolize_keys

      Ai::PromptCatalog.render("character_bible", values.transform_values { |value| value.to_s.strip })
    end
  end
end
