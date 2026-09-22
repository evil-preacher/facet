require "json"
require "set"

module Ai
  class GroundedSummarySchema
    RESPONSE_SCHEMA = {
      name: "grounded_summary",
      schema: {
        type: "object",
        additionalProperties: false,
        required: %w[summary source_message_ids],
        properties: {
          summary: { type: "string" },
          source_message_ids: {
            type: "array",
            items: { type: "integer" }
          }
        }
      }
    }.freeze

    class InvalidOutput < StandardError; end

    def self.parse(text:, allowed_message_ids:)
      document = JSON.parse(text)
      allowed_ids = allowed_message_ids.map { |id| Integer(id) }.to_set
      valid_shape = document.is_a?(Hash) && document.keys.sort == %w[source_message_ids summary]
      raise InvalidOutput, "invalid response shape" unless valid_shape

      summary = document["summary"]
      source_ids = document["source_message_ids"]
      raise InvalidOutput, "invalid summary" unless summary.is_a?(String) && summary.strip.present? &&
        summary.length <= 100_000
      raise InvalidOutput, "invalid source ids" unless source_ids.is_a?(Array) && source_ids.any? &&
        source_ids.uniq.length == source_ids.length &&
        source_ids.all? { |id| id.is_a?(Integer) && allowed_ids.include?(id) }

      { summary: summary.squish, source_message_ids: source_ids }
    rescue JSON::ParserError, TypeError, ArgumentError => error
      raise InvalidOutput, error.message
    end
  end
end
