require "json"
require "set"
require "time"

module Memories
  module Extraction
    class Schema
      ACTIONS = %w[create supersede contradiction].freeze
      SENSITIVITIES = %w[normal sensitive prohibited].freeze
      CANDIDATE_KEYS = %w[
        action
        kind
        content
        evidence_quote
        importance
        occurred_at
        source_message_ids
        existing_memory_id
        sensitivity
      ].freeze

      RESPONSE_SCHEMA = {
        name: "memory_candidates",
        schema: {
          type: "object",
          additionalProperties: false,
          required: [ "candidates" ],
          properties: {
            candidates: {
              type: "array",
              items: {
                type: "object",
                additionalProperties: false,
                required: CANDIDATE_KEYS,
                properties: {
                  action: { type: "string", enum: ACTIONS },
                  kind: { type: "string", enum: Memory::KINDS },
                  content: { type: "string" },
                  evidence_quote: { type: "string" },
                  importance: { type: "integer" },
                  occurred_at: {
                    anyOf: [
                      { type: "string" },
                      { type: "null" }
                    ]
                  },
                  source_message_ids: {
                    type: "array",
                    items: { type: "integer" }
                  },
                  existing_memory_id: {
                    anyOf: [
                      { type: "integer" },
                      { type: "null" }
                    ]
                  },
                  sensitivity: { type: "string", enum: SENSITIVITIES }
                }
              }
            }
          }
        }
      }.freeze

      class InvalidOutput < StandardError; end

      def self.parse(text:, allowed_message_ids:, allowed_memory_ids:, source_message_texts:)
        new(
          text: text,
          allowed_message_ids: allowed_message_ids,
          allowed_memory_ids: allowed_memory_ids,
          source_message_texts: source_message_texts
        ).parse
      end

      def initialize(text:, allowed_message_ids:, allowed_memory_ids:, source_message_texts:)
        @text = text
        @allowed_message_ids = allowed_message_ids.map { |id| Integer(id) }.to_set
        @allowed_memory_ids = allowed_memory_ids.map { |id| Integer(id) }.to_set
        @source_message_texts = source_message_texts
      end

      def parse
        document = JSON.parse(@text)
        invalid!("root must contain only candidates") unless document.is_a?(Hash) &&
          document.keys == [ "candidates" ]
        candidates = document.fetch("candidates")
        invalid!("candidates must be an array") unless candidates.is_a?(Array) && candidates.length <= 12

        candidates.filter_map { |candidate| validate_candidate(candidate) }
      rescue JSON::ParserError, TypeError, ArgumentError, KeyError => error
        raise InvalidOutput, error.message
      end

      private

      def validate_candidate(candidate)
        invalid!("candidate has an invalid shape") unless candidate.is_a?(Hash) &&
          candidate.keys.sort == CANDIDATE_KEYS.sort
        invalid!("invalid action") unless ACTIONS.include?(candidate["action"])
        invalid!("invalid kind") unless Memory::KINDS.include?(candidate["kind"])
        invalid!("invalid content") unless candidate["content"].is_a?(String) &&
          candidate["content"].strip.present? &&
          candidate["content"].length <= Memory::MAX_CONTENT_LENGTH
        invalid!("invalid importance") unless candidate["importance"].is_a?(Integer) &&
          candidate["importance"].between?(1, 100)
        invalid!("invalid sensitivity") unless SENSITIVITIES.include?(candidate["sensitivity"])

        source_ids = candidate["source_message_ids"]
        invalid!("invalid source messages") unless source_ids.is_a?(Array) &&
          source_ids.length.between?(1, 3) &&
          source_ids.uniq.length == source_ids.length &&
          source_ids.all? { |id| id.is_a?(Integer) && @allowed_message_ids.include?(id) }

        quote = candidate["evidence_quote"]
        return unless quote.is_a?(String) &&
          quote.strip.length.between?(10, 500) &&
          !quote.include?("?") &&
          source_ids.any? { |id| direct_user_evidence?(@source_message_texts[id].to_s, quote.strip) }

        existing_id = candidate["existing_memory_id"]
        if candidate["action"] == "create"
          invalid!("create cannot reference an existing memory") unless existing_id.nil?
        else
          invalid!("replacement must reference an active memory") unless existing_id.is_a?(Integer) &&
            @allowed_memory_ids.include?(existing_id)
        end

        candidate.merge("occurred_at" => parse_occurred_at(candidate["occurred_at"]))
      end

      def direct_user_evidence?(source_text, quote)
        spoken_text = source_text.gsub(/\*[^*]*\*/m, " ")
        return false if question_only_without_self_report?(spoken_text)
        return false if character_directed_without_self_report?(quote)

        spoken_text.include?(quote)
      end

      def character_directed_without_self_report?(quote)
        addresses_character = quote.match?(/(?:^|[^\p{L}])(?:ты|тебя|тебе|тобой|твой|твоя|твоё|твои|твою|you|your)(?:$|[^\p{L}])/i)
        return false unless addresses_character

        !quote.match?(/я люблю|мне нравится|я предпочитаю|мне важно|я не люблю|я не хочу|я всегда|я обычно|\bi like\b|\bi prefer\b|\bi always\b|\bi usually\b|\bi don't want\b/i)
      end

      def question_only_without_self_report?(text)
        first_question = text.split("?", 2).first.to_s
        return false unless text.include?("?") && !first_question.match?(/[.!]/)

        !first_question.match?(/я люблю|мне нравится|я предпочитаю|\bi like\b|\bi love\b|\bi prefer\b/i)
      end

      def parse_occurred_at(value)
        return if value.nil?

        Time.iso8601(value)
      rescue ArgumentError
        invalid!("invalid occurred_at")
      end

      def invalid!(message)
        raise InvalidOutput, message
      end
    end
  end
end
