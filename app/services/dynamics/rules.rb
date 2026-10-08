module Dynamics
  class Rules
    VERSION = 2
    BASE_SLOW = { "trust" => 50, "closeness" => 0, "tension" => 0 }.freeze
    BASE_FAST = { "warmth" => 0, "irritation" => 0 }.freeze
    V1_CHANGES = {
      "trust" => { "trust" => 5, "warmth" => 20 },
      "conflict" => { "trust" => -4, "tension" => 8, "irritation" => 30 },
      "repair" => { "tension" => -6, "warmth" => 10, "irritation" => -12 },
      "closeness" => { "closeness" => 5, "warmth" => 15 }
    }.freeze
    CHANGES = V1_CHANGES.merge("jealousy" => {}, "attraction" => {}, "boundary" => {}, "space_request" => {}).freeze
    HALF_LIFE_HOURS = { "warmth" => 24.0, "irritation" => 8.0 }.freeze

    def self.transition(slow:, fast:, observed_at:, kind:, now:, version: VERSION)
      changes = case version
      when 1 then V1_CHANGES
      when 2 then CHANGES
      else raise ArgumentError, "unknown rules version"
      end
      raise ArgumentError, "unknown event" unless changes.key?(kind) || kind == "none"

      slow = BASE_SLOW.merge(slow.stringify_keys)
      fast = BASE_FAST.merge(fast.stringify_keys)
      hours = observed_at ? [ (now - observed_at) / 1.hour, 0 ].max : 0
      fast = fast.transform_values.with_index do |value, index|
        key = fast.keys.fetch(index)
        (value * (0.5**(hours / HALF_LIFE_HOURS.fetch(key)))).round
      end
      reasons = {}
      changes.fetch(kind, {}).each do |key, amount|
        target = slow.key?(key) ? slow : fast
        before = target.fetch(key)
        target[key] = (before + amount).clamp(0, 100)
        reasons[key] = { "event" => kind, "delta" => target[key] - before } if target[key] != before
      end
      [ slow, fast, reasons ]
    end
  end
end
