require "json"

module Ai
  module Initiatives
    class Decide
      SCHEMA = {
        name: "initiative_policy_decision",
        schema: {
          type: "object", additionalProperties: false,
          required: %w[send_message channel topic motivation intensity],
          properties: {
            send_message: { type: "boolean" },
            channel: { type: "string", enum: %w[none in_app email] },
            topic: { type: "string" },
            motivation: { type: "string" },
            intensity: { type: "string", enum: %w[low medium high] }
          }
        }
      }.freeze
      Result = Data.define(:decision, :topic, :motivation, :intensity, :error_code)

      def self.call(attempt:, memories:, recent_messages:, gateway:, now: Time.current)
        personality = attempt.personality
        relationship = personality.relationship_state
        state_summary = relationship&.summary.to_s.first(4_000)
        if personality.dynamic_state_enabled?
          interpretation = Dynamics::Interpret.call(relationship_state: relationship,
                                                    emotional_state: personality.emotional_state, now: now)
          state_summary = [ state_summary, interpretation ].reject(&:blank?).join("\n")
        end
        response = Ai::Request.call(
          user: personality.user, personality: personality, purpose: :initiative,
          model: personality.utility_model, gateway: gateway, provider: attempt.ai_provider,
          response_schema: SCHEMA, temperature: 0.1, max_output_tokens: 300, now: now,
          input: [
            { role: "developer", content: Ai::PromptCatalog.content("initiative_decision") },
            { role: "developer", content: Ai::PromptCatalog.render("initiative_character_bible",
              character_bible: attempt.personality_version.content) },
            { role: "user", content: JSON.generate(
              relationship_state: state_summary,
              approved_memories: memories.map(&:content),
              thread_summary: attempt.conversation_thread.summary.to_s.first(4_000),
              recent_messages: recent_messages,
              last_user_message_at: attempt.source_message.created_at.iso8601,
              recent_initiative_motivations: personality.initiative_attempts.completed
                .order(completed_at: :desc).limit(5).pluck(:motivation).compact,
              user_intensity: personality.initiative_intensity,
              allowed_channels: personality.initiative_email_enabled? ? %w[in_app email] : %w[in_app]
            ) }
          ]
        )
        return Result.new(decision: nil, topic: nil, motivation: nil, intensity: nil,
                          error_code: response.error_code) unless response.success?

        parsed = JSON.parse(response.response.text)
        valid = parsed.is_a?(Hash) && parsed.keys.sort == %w[channel intensity motivation send_message topic] &&
          [ true, false ].include?(parsed["send_message"]) &&
          %w[none in_app email].include?(parsed["channel"]) &&
          parsed["topic"].is_a?(String) && parsed["topic"].length <= 240 &&
          parsed["motivation"].is_a?(String) && parsed["motivation"].length <= 240 &&
          %w[low medium high].include?(parsed["intensity"])
        return invalid unless valid
        return invalid if parsed["send_message"] &&
          (parsed["topic"].strip.blank? || parsed["motivation"].strip.blank?)
        return invalid if parsed["send_message"] && parsed["channel"] == "none"
        return invalid if !parsed["send_message"] && parsed["channel"] != "none"

        decision = { "none" => "NO_ACTION", "in_app" => "IN_APP", "email" => "EMAIL" }.fetch(parsed["channel"])
        Result.new(decision: decision,
                   topic: parsed["topic"].strip, motivation: parsed["motivation"].strip,
                   intensity: parsed["intensity"], error_code: nil)
      rescue JSON::ParserError
        invalid
      end

      def self.invalid
        Result.new(decision: nil, topic: nil, motivation: nil, intensity: nil,
                   error_code: "invalid_decision")
      end
      private_class_method :invalid
    end
  end
end
