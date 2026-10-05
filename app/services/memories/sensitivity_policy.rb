module Memories
  class SensitivityPolicy
    PROHIBITED_PATTERNS = [
      /\b(?:password|парол[ья]|passcode|пин[- ]?код)\b/i,
      /\b(?:api|access|refresh)[_-]?token\b/i,
      /-----BEGIN (?:RSA |EC |OPENSSH )?PRIVATE KEY-----/i,
      /\b(?:\d[ -]*?){13,19}\b/
    ].freeze
    SENSITIVE_PATTERNS = [
      /(?<!\p{L})(?:секс\p{L}*|сексуальн\p{L}*|мастурб\p{L}*|фаллоимит\p{L}*|анальн\p{L}*|эротич\p{L}*)(?!\p{L})/i,
      /\b(?:sex|sexual|masturbat\w*|dildo\w*|anal|erotic\w*)\b/i
    ].freeze

    def self.classify(content:, model_sensitivity:)
      return :prohibited if model_sensitivity == "prohibited"
      return :prohibited if PROHIBITED_PATTERNS.any? { |pattern| content.match?(pattern) }
      return :sensitive if model_sensitivity == "sensitive"
      return :sensitive if SENSITIVE_PATTERNS.any? { |pattern| content.match?(pattern) }

      :normal
    end
  end
end
