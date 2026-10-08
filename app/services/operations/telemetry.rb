module Operations
  class Telemetry
    FIELDS = %i[
      record_id status purpose provider model error_code latency_ms first_token_latency_ms
      input_tokens cached_input_tokens output_tokens cost_microusd attempts_count
      generation_run_id personality_id
      decision decision_reason intensity dynamic_state_revision_id
    ].freeze
    EVENTS = %w[model_call generation_run memory_extraction initiative initiative_decision initiative_email_delivery budget_rejection].freeze

    def self.emit(event, **attributes)
      raise ArgumentError, "Unknown telemetry event" unless EVENTS.include?(event.to_s)

      payload = { event: event.to_s, at: Time.current.iso8601(3) }
      attributes.slice(*FIELDS).each { |key, value| payload[key] = value if value }
      Rails.logger.info(JSON.generate(payload))
    end
  end
end
