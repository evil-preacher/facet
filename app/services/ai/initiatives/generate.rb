require "json"

module Ai
  module Initiatives
    class Generate
      DECISION_SCHEMA = {
        name: "initiative_decision",
        schema: {
          type: "object", additionalProperties: false,
          required: %w[send_message topic],
          properties: {
            send_message: { type: "boolean" },
            topic: { type: "string" }
          }
        }
      }.freeze
      DECISION_RULES = <<~TEXT.freeze
      [Prompt text removed from public history]
      TEXT
      MESSAGE_RULES = <<~TEXT.freeze
      [Prompt text removed from public history]
      TEXT
      TRANSIENT_ERRORS = %w[timeout rate_limit provider_error].freeze

      Result = Data.define(:status, :error_code, :message)

      def self.call(**arguments) = new(**arguments).call

      def initialize(attempt:, gateway: nil, now: Time.current)
        @attempt = attempt
        @personality = attempt.personality
        @thread = attempt.conversation_thread
        @gateway = gateway || ProviderRegistry.gateway_for(attempt.ai_provider)
        @now = now
      end

      def call
        return Result.new(status: :skipped, error_code: nil, message: nil) unless claim!
        return skip! unless eligible_now?

        @memories = Memories::Retrieve.call(personality: personality, query: attempt.source_message.content).memories
        topic = attempt.topic.presence || choose_topic
        return topic if topic.is_a?(Result)
        return skip! if topic.blank?
        return skip! unless eligible_now?

        attempt.update!(topic: topic)
        response = Ai::Request.call(
          user: personality.user, personality: personality, purpose: :initiative,
          model_role: :conversation, model: personality.conversation_model,
          input: message_input(topic), max_output_tokens: 600,
          gateway: gateway, provider: attempt.ai_provider, now: now
        )
        return request_failure!(response.error_code) unless response.success?

        persist_message!(response.response.text)
      end

      private

      attr_reader :attempt, :personality, :thread, :gateway, :now

      def claim!
        attempt.with_lock do
          return false if attempt.completed? || attempt.skipped? || attempt.failed?
          return false if attempt.running? && attempt.started_at && attempt.started_at > now - 1.hour

          attempt.update!(status: :running, started_at: now, error_code: nil)
        end
        true
      end

      def eligible_now?(check_budget: true)
        result = Eligibility.call(personality: personality, now: now, except_attempt: attempt,
                                  check_budget: check_budget)
        result.eligible && result.thread.id == thread.id &&
          result.last_user_message.id == attempt.source_message_id
      end

      def choose_topic
        response = Ai::Request.call(
          user: personality.user, personality: personality, purpose: :initiative,
          model: personality.utility_model, input: decision_input,
          response_schema: DECISION_SCHEMA, temperature: 0.1, max_output_tokens: 300,
          gateway: gateway, provider: attempt.ai_provider, now: now
        )
        return request_failure!(response.error_code) unless response.success?

        parsed = JSON.parse(response.response.text)
        valid = parsed.is_a?(Hash) && parsed.keys.sort == %w[send_message topic] &&
          [ true, false ].include?(parsed["send_message"]) && parsed["topic"].is_a?(String) &&
          parsed["topic"].length <= 240
        return fail_with!("invalid_decision") unless valid

        parsed["send_message"] ? parsed["topic"].strip.presence : nil
      rescue JSON::ParserError
        fail_with!("invalid_decision")
      end

      def decision_input
        [
          { role: "developer", content: DECISION_RULES },
          { role: "user", content: JSON.generate(
            relationship_state: personality.relationship_state&.summary.to_s.first(4_000),
            approved_memories: @memories.map(&:content),
            thread_summary: thread.summary.to_s.first(4_000),
            recent_messages: recent_messages,
            last_user_message_at: attempt.source_message.created_at.iso8601
          ) }
        ]
      end

      def message_input(topic)
        items = [ { role: "developer", content: PromptBuilder::APPLICATION_RULES } ]
        platform = AiPlatformPrompt.active_for(provider: attempt.ai_provider)
        if Rails.configuration.x.ai.platform_prompt_required && platform.nil?
          raise ValidationError, "No active conversation platform prompt"
        end
        items << { role: "developer", content: platform.content } if platform &&
          Rails.configuration.x.ai.platform_prompt_enabled
        items << { role: "developer", content: "Character Bible:\n#{attempt.personality_version.content}" }
        items << { role: "developer", content: MESSAGE_RULES }
        items << { role: "user", content: JSON.generate(
          topic: topic, relationship_state: personality.relationship_state&.summary.to_s.first(4_000),
          approved_memories: @memories.map(&:content), thread_summary: thread.summary.to_s.first(4_000),
          recent_messages: recent_messages
        ) }
        items
      end

      def recent_messages
        thread.messages.completed.order(position: :desc).limit(8).reverse.map do |message|
          { role: message.role, content: message.content.to_s.first(2_000) }
        end
      end

      def persist_message!(content)
        thread.with_lock do
          return skip! unless eligible_now?(check_budget: false)
          return skip! if Message.unread_initiatives.where(conversation_thread: thread).exists?

          message = thread.messages.create!(
            personality_version: attempt.personality_version,
            position: thread.messages.maximum(:position).to_i + 1,
            role: :assistant, status: :completed, content: content,
            language: LanguageDetector.call(content), initiated_by: "personality", read_at: nil
          )
          thread.update!(last_message_at: message.created_at)
          attempt.update!(status: :completed, message: message, completed_at: now, started_at: nil)
          Result.new(status: :completed, error_code: nil, message: message)
        end
      end

      def request_failure!(code)
        if TRANSIENT_ERRORS.include?(code)
          attempt.update!(status: :pending, started_at: nil, error_code: code)
          raise RetryableInitiativeError.new(attempt_id: attempt.id, error_code: code)
        end
        return skip! if code == "budget_exceeded"

        fail_with!(code)
      end

      def skip!
        attempt.update!(status: :skipped, started_at: nil, completed_at: now)
        Result.new(status: :skipped, error_code: nil, message: nil)
      end

      def fail_with!(code)
        attempt.update!(status: :failed, started_at: nil, completed_at: now, error_code: code)
        Result.new(status: :failed, error_code: code, message: nil)
      end
    end
  end
end
