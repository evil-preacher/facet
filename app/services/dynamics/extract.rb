module Dynamics
  # Only direct, first-person statements count as confirmed interaction events.
  # A wider model-based extractor can replace this contract without changing replay.
  class Extract
    RULES_VERSION = 1
    PATTERNS = {
      "trust" => /\A(?:я тебе доверяю|i trust you)(?:[.!\s]|\z)/i,
      "conflict" => /\A(?:я злюсь на тебя|i am angry with you|i'm angry with you)(?:[.!\s]|\z)/i,
      "repair" => /\A(?:прости меня|извини меня|i am sorry|i'm sorry)(?:[.!\s]|\z)/i,
      "closeness" => /\A(?:мне нравится быть с тобой|i like being with you)(?:[.!\s]|\z)/i
    }.freeze

    def self.call(message:)
      content = message.content.to_s.strip
      kind = if content.match?(/[?*]/) || content.match?(/\b(?:если бы|what if|if i)\b/i)
        "none"
      else
        PATTERNS.find { |_name, pattern| pattern.match?(content) }&.first || "none"
      end
      { "kind" => kind, "extractor" => "explicit-v1", "source_message_ids" => kind == "none" ? [] : [ message.id ] }
    end
  end
end
