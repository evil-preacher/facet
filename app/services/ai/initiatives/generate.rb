module Ai
  module Initiatives
    class Generate
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
        return no_action!("ineligible") unless eligible_now?
        reason = Policy.call(personality: personality, now: now)
        return no_action!(reason) if reason

        @memories = Memories::Retrieve.call(personality: personality, query: attempt.source_message.content).memories
        unless %w[IN_APP EMAIL].include?(attempt.decision) && attempt.topic.present?
          decision = Decide.call(attempt: attempt, memories: @memories,
                                 recent_messages: recent_messages, gateway: gateway, now: now)
          return request_failure!(decision.error_code) if decision.error_code

          record_decision!(decision)
          return skip! if decision.decision == "NO_ACTION"
        end
        personality.reload
        recheck_at = Time.current
        return no_action!("ineligible") unless eligible_now?(at: recheck_at)
        reason = Policy.call(personality: personality, now: recheck_at,
                             motivation: attempt.motivation, intensity: attempt.intensity,
                             channel: attempt.decision)
        return no_action!(reason) if reason

        response = Ai::Request.call(
          user: personality.user, personality: personality, purpose: :initiative,
          model_role: :conversation, model: personality.conversation_model,
          input: message_input(attempt.topic), max_output_tokens: 600,
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

      def eligible_now?(check_budget: true, at: now)
        result = Eligibility.call(personality: personality, now: at, except_attempt: attempt,
                                  check_budget: check_budget)
        result.eligible && result.thread.id == thread.id &&
          result.last_user_message.id == attempt.source_message_id
      end

      def record_decision!(decision)
        attempt.update!(decision: decision.decision, topic: decision.topic,
                        motivation: decision.motivation, intensity: decision.intensity,
                        decided_at: now, decision_reason: decision.decision == "NO_ACTION" ? "model_declined" : nil,
                        dynamic_state_revision: current_dynamic_revision)
      end

      def no_action!(reason)
        attempt.update!(decision: "NO_ACTION", decision_reason: reason, decided_at: now,
                        dynamic_state_revision: current_dynamic_revision)
        skip!
      end

      def current_dynamic_revision
        personality.relationship_state&.dynamic_revisions&.last if personality.dynamic_state_enabled?
      end

      def message_input(topic)
        items = [ { role: "developer", content: Ai::PromptCatalog.content("application_rules") } ]
        platform = AiPlatformPrompt.active_for(provider: attempt.ai_provider)
        if Rails.configuration.x.ai.platform_prompt_required && platform.nil?
          raise ValidationError, "No active conversation platform prompt"
        end
        items << { role: "developer", content: platform.content } if platform &&
          Rails.configuration.x.ai.platform_prompt_enabled
        items << { role: "developer", content: Ai::PromptCatalog.render("initiative_character_bible",
          character_bible: attempt.personality_version.content) }
        items << { role: "developer", content: Ai::PromptCatalog.content("initiative_message") }
        dynamic_context = if personality.dynamic_state_enabled?
          Dynamics::Interpret.call(relationship_state: personality.relationship_state,
                                   emotional_state: personality.emotional_state, now: now)
        end
        items << { role: "user", content: JSON.generate(
          topic: topic, relationship_state: personality.relationship_state&.summary.to_s.first(4_000),
          delivery_channel: attempt.decision == "EMAIL" ? "email_and_in_app" : "in_app",
          dynamic_state: dynamic_context,
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
        personality.with_lock do
          thread.with_lock do
            recheck_at = Time.current
            return no_action!("ineligible") unless eligible_now?(check_budget: false, at: recheck_at)
            reason = Policy.call(personality: personality, now: recheck_at,
                                 motivation: attempt.motivation, intensity: attempt.intensity,
                                 channel: attempt.decision)
            return no_action!(reason) if reason
            return no_action!("unread") if Message.unread_initiatives.where(conversation_thread: thread).exists?

            message = thread.messages.create!(
              personality_version: attempt.personality_version,
              position: thread.messages.maximum(:position).to_i + 1,
              role: :assistant, status: :completed, content: content,
              language: LanguageDetector.call(content), initiated_by: "personality", read_at: nil
            )
            thread.update!(last_message_at: message.created_at)
            attempt.update!(status: :completed, message: message, completed_at: recheck_at, started_at: nil)
            if attempt.decision == "EMAIL"
              delivery = attempt.create_initiative_email_delivery!
              Outbox::Publish.call(
                event_key: "deliver-initiative-email:#{attempt.id}",
                job_class: Ai::DeliverInitiativeEmailJob,
                arguments: [ delivery.id ]
              )
            end
            Result.new(status: :completed, error_code: nil, message: message)
          end
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
