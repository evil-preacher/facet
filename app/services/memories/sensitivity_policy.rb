module Memories
  class SensitivityPolicy
    PROHIBITED_PATTERNS = [
      /\b(?:password|парол[ья]|passcode|пин[- ]?код)\b/i,
      /\b(?:api|access|refresh)[_-]?token\b/i,
      /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i,
      /\b(?:\d[ -]*?){13,19}\b/
    ].freeze

    def self.classify(content:, model_sensitivity:)
      return :prohibited if model_sensitivity == "prohibited"
      return :prohibited if PROHIBITED_PATTERNS.any? { |pattern| content.match?(pattern) }
      return :sensitive if model_sensitivity == "sensitive"

      :normal
    end
  end
end
