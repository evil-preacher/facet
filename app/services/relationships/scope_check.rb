require "json"

module Relationships
  class ScopeCheck
    RESPONSE_SCHEMA = {
      name: "relationship_scope_check",
      schema: {
        type: "object",
        additionalProperties: false,
        required: %w[valid violations],
        properties: {
          valid: { type: "boolean" },
          violations: { type: "array", items: { type: "string" } }
        }
      }
    }.freeze

    INSTRUCTIONS = <<~TEXT.freeze
      [Prompt text removed from public history]
    TEXT

    Result = Data.define(:valid, :error_code) do
      def success? = error_code.nil?
    end

    def self.call(personality:, provider:, summary:, messages:, gateway:, now:, clock:)
      return Result.new(valid: true, error_code: nil) if summary.blank?

      request = Ai::Request.call(
        user: personality.user, personality: personality, purpose: :memory_consolidation,
        model: personality.utility_model,
        input: [
          { role: "developer", content: INSTRUCTIONS },
          { role: "user", content: JSON.pretty_generate(
            proposed_summary: summary,
            evidence_messages: messages.map do |message|
              { id: message.id, role: message.role, content: message.content }
            end
          ) }
        ],
        response_schema: RESPONSE_SCHEMA, temperature: 0.0, max_output_tokens: 500,
        gateway: gateway, provider: provider, now: now, clock: clock
      )
      return Result.new(valid: false, error_code: request.error_code) unless request.success?

      document = JSON.parse(request.response.text)
      valid_shape = document.is_a?(Hash) && document.keys.sort == %w[valid violations] &&
        [ true, false ].include?(document["valid"]) && document["violations"].is_a?(Array) &&
        document["violations"].all? { |item| item.is_a?(String) }
      return Result.new(valid: false, error_code: "invalid_scope_check") unless valid_shape
      return Result.new(valid: false, error_code: "invalid_scope_check") if document["valid"] &&
        document["violations"].any?

      Result.new(valid: document["valid"], error_code: ("scope_violation" unless document["valid"]))
    rescue JSON::ParserError
      Result.new(valid: false, error_code: "invalid_scope_check")
    end
  end
end
