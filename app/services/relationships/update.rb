module Relationships
  class Update
    TRANSIENT_ERRORS = %w[timeout rate_limit provider_error].freeze
    Result = Data.define(:version, :error_code) do
      def success? = error_code.nil?
    end

    def self.call(**arguments) = new(**arguments).call

    def initialize(generation_run:, gateway: nil, now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @generation_run = generation_run
      @personality = generation_run.conversation_thread.personality
      @gateway = gateway || Ai::ProviderRegistry.gateway_for(generation_run.ai_provider)
      @now = now
      @clock = clock
    end

    def call
      return Result.new(version: existing_version, error_code: nil) if existing_version
      return Result.new(version: nil, error_code: nil) if generation_run.relationship_update_processed_at.present?
      return Result.new(version: nil, error_code: nil) unless valid_target?

      state = find_or_create_state
      base_revision = state.revision
      messages = [ generation_run.user_message, generation_run.assistant_message ]
      request = Ai::Request.call(
        user: personality.user, personality: personality, purpose: :memory_consolidation,
        model: personality.utility_model,
        input: Update::Prompt.call(previous_summary: state.summary, messages: messages,
                                   language: summary_language(messages)),
        response_schema: Update::Schema::RESPONSE_SCHEMA,
        temperature: 0.1, max_output_tokens: 1_500, gateway: gateway,
        provider: generation_run.ai_provider, now: now, clock: clock
      )
      return request_failure(request) unless request.success?

      parsed = Update::Schema.parse(
        text: request.response.text, previous_summary: state.summary,
        allowed_message_ids: messages.map(&:id)
      )
      if parsed.fetch(:status) != "unchanged"
        scope_check = ScopeCheck.call(
          personality: personality, provider: generation_run.ai_provider,
          summary: parsed.fetch(:summary), messages: messages,
          gateway: gateway, now: now, clock: clock
        )
        return scope_check_failure(scope_check) unless scope_check.success?
      end
      version = persist!(state, base_revision, parsed, request.model_call)
      Result.new(version: version, error_code: nil)
    rescue Update::Schema::InvalidOutput
      Result.new(version: nil, error_code: "invalid_output")
    end

    private

    attr_reader :generation_run, :personality, :gateway, :now, :clock

    def existing_version
      @existing_version ||= RelationshipStateVersion.find_by(generation_run: generation_run)
    end

    def valid_target?
      generation_run.completed? && generation_run.assistant_message&.completed?
    end

    def summary_language(messages)
      messages.filter_map { |message| message.language.presence_in(%w[ru en]) }.first || I18n.default_locale.to_s
    end

    def find_or_create_state
      personality.relationship_state || personality.create_relationship_state!
    rescue ActiveRecord::RecordNotUnique
      personality.reload.relationship_state
    end

    def persist!(state, base_revision, parsed, model_call)
      state.with_lock do
        generation_run.reload
        existing = RelationshipStateVersion.find_by(generation_run: generation_run)
        return existing if existing
        return if generation_run.relationship_update_processed_at.present?
        if state.revision != base_revision
          raise Ai::RetryableContextUpdateError.new(
            generation_run_id: generation_run.id, error_code: "stale_context"
          )
        end

        model_call.update!(generation_run: generation_run)
        version = unless parsed.fetch(:status) == "unchanged"
          revision = state.revision + 1
          created = state.versions.create!(
            generation_run: generation_run,
            source_version: state.versions.find_by(revision: base_revision),
            model_call: model_call,
            revision: revision,
            summary: parsed.fetch(:summary),
            source_message_ids: parsed.fetch(:source_message_ids),
            reason: parsed.fetch(:status) == "cleanup" ? :cleanup : :model_update
          )
          state.update!(summary: created.summary, revision: revision)
          created
        end
        generation_run.update!(relationship_update_processed_at: now)
        version
      end
    end

    def request_failure(request)
      if TRANSIENT_ERRORS.include?(request.error_code)
        raise Ai::RetryableContextUpdateError.new(
          generation_run_id: generation_run.id, error_code: request.error_code
        )
      end
      Result.new(version: nil, error_code: request.error_code)
    end

    def scope_check_failure(scope_check)
      if TRANSIENT_ERRORS.include?(scope_check.error_code)
        raise Ai::RetryableContextUpdateError.new(
          generation_run_id: generation_run.id, error_code: scope_check.error_code
        )
      end
      Result.new(version: nil, error_code: scope_check.error_code)
    end
  end
end
