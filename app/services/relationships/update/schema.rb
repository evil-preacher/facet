require "json"
require "set"

class Relationships::Update::Schema
  RESPONSE_SCHEMA = {
    name: "relationship_update",
    schema: {
      type: "object",
      additionalProperties: false,
      required: %w[status summary source_message_ids],
      properties: {
        status: { type: "string", enum: %w[changed cleanup unchanged] },
        summary: { type: "string" },
        source_message_ids: { type: "array", items: { type: "integer" } }
      }
    }
  }.freeze

  UPDATE_RESPONSE_SCHEMA = {
    name: "durable_relationship_update",
    schema: {
      type: "object",
      additionalProperties: false,
      required: %w[status summary source_message_ids durable_evidence_quote],
      properties: RESPONSE_SCHEMA.fetch(:schema).fetch(:properties).merge(
        durable_evidence_quote: { anyOf: [ { type: "string" }, { type: "null" } ] }
      )
    }
  }.freeze

  class InvalidOutput < StandardError; end

  def self.parse(text:, previous_summary:, allowed_message_ids:)
    document = JSON.parse(text)
    raise InvalidOutput, "invalid response shape" unless document.is_a?(Hash) &&
      document.keys.sort == %w[source_message_ids status summary]

    status = document.fetch("status")
    summary = document.fetch("summary")
    ids = document.fetch("source_message_ids")
    allowed_ids = allowed_message_ids.to_set
    raise InvalidOutput, "invalid summary" unless summary.is_a?(String) && summary.length <= 100_000
    raise InvalidOutput, "invalid source ids" unless ids.is_a?(Array) && ids.uniq.length == ids.length &&
      ids.all? { |id| id.is_a?(Integer) && allowed_ids.include?(id) }

    case status
    when "unchanged"
      raise InvalidOutput, "unchanged state must be copied exactly" unless summary == previous_summary && ids.empty?
    when "changed"
      raise InvalidOutput, "changed state needs evidence" unless summary.strip.present? &&
        summary != previous_summary && ids.any?
    when "cleanup"
      raise InvalidOutput, "cleanup cannot cite the new turn" unless summary != previous_summary && ids.empty?
    else
      raise InvalidOutput, "invalid status"
    end

    { status: status, summary: summary, source_message_ids: ids }
  rescue JSON::ParserError, TypeError, ArgumentError => error
    raise InvalidOutput, error.message
  end

  def self.parse_update(text:, previous_summary:, user_message:, allowed_message_ids:)
    document = JSON.parse(text)
    raise InvalidOutput, "invalid update shape" unless document.is_a?(Hash) &&
      document.keys.sort == %w[durable_evidence_quote source_message_ids status summary]

    quote = document.delete("durable_evidence_quote")
    parsed = parse(
      text: document.to_json,
      previous_summary: previous_summary,
      allowed_message_ids: allowed_message_ids
    )
    if parsed.fetch(:status) == "changed"
      return parsed if durable_user_evidence?(quote, user_message) &&
        parsed.fetch(:source_message_ids).include?(user_message.id)

      return { status: "unchanged", summary: previous_summary, source_message_ids: [] }
    end

    raise InvalidOutput, "non-change cannot cite durable evidence" unless quote.nil?

    parsed
  rescue JSON::ParserError, TypeError, ArgumentError => error
    raise InvalidOutput, error.message
  end

  def self.durable_user_evidence?(quote, user_message)
    return false unless quote.is_a?(String) && quote.strip.length >= 15 && !quote.include?("?")

    user_message.content.to_s.gsub(/\*[^*]*\*/m, " ").include?(quote.strip)
  end
end
