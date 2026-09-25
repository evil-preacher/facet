module Relationships
  class Consolidate
    MAX_EVIDENCE_CHARS = 60_000
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
      return Result.new(version: nil, error_code: nil) if generation_run.relationship_consolidated_at.present?
      return Result.new(version: nil, error_code: nil) unless generation_run.completed? &&
        generation_run.assistant_message&.completed?
      unless generation_run.relationship_update_processed_at.present? || generation_run.relationship_state_version
        raise Ai::RetryableContextUpdateError.new(
          generation_run_id: generation_run.id, error_code: "relationship_update_pending"
        )
      end

      state = personality.relationship_state
      return mark_without_evidence unless state

      base_revision = state.revision
      base_cursor = state.last_consolidated_message_id
      messages, complete_evidence = evidence_batch(state)
      return mark_without_evidence if messages.empty?

      request = Ai::Request.call(
        user: personality.user, personality: personality, purpose: :memory_consolidation,
        model: personality.utility_model,
        input: Consolidate::Prompt.call(
          previous_summary: state.summary, messages: messages,
          complete_evidence: complete_evidence, language: summary_language
        ),
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
      version = persist!(state, base_revision, base_cursor, messages.last.id, parsed, request.model_call)
      Result.new(version: version, error_code: nil)
    rescue Update::Schema::InvalidOutput
      Result.new(version: nil, error_code: "invalid_output")
    end

    private

    attr_reader :generation_run, :personality, :gateway, :now, :clock

    def evidence_batch(state)
      ids = state.versions.pluck(:source_message_ids).flatten.uniq
      messages = Message.joins(:conversation_thread)
        .where(id: ids, conversation_threads: { personality_id: personality.id })
        .reorder(:id).to_a
      return [ [], true ] if messages.empty?

      cursor = state.last_consolidated_message_id
      pending = messages.select { |message| message.id > cursor.to_i }
      pending = messages if pending.empty?
      selected = []
      length = 0
      pending.each do |message|
        break if selected.any? && length + message.content.length > MAX_EVIDENCE_CHARS

        selected << message
        length += message.content.length
      end
      [ selected, selected.length == messages.length ]
    end

    def summary_language
      generation_run.user_message.language.presence_in(%w[ru en]) ||
        generation_run.assistant_message.language.presence_in(%w[ru en]) || I18n.default_locale.to_s
    end

    def persist!(state, base_revision, base_cursor, last_message_id, parsed, model_call)
      state.with_lock do
        generation_run.reload
        return if generation_run.relationship_consolidated_at.present?
        if state.revision != base_revision || state.last_consolidated_message_id != base_cursor
          raise Ai::RetryableContextUpdateError.new(
            generation_run_id: generation_run.id, error_code: "stale_context"
          )
        end

        model_call.update!(generation_run: generation_run)
        version = unless parsed.fetch(:status) == "unchanged"
          revision = state.revision + 1
          created = state.versions.create!(
            source_version: state.versions.find_by(revision: base_revision),
            model_call: model_call, revision: revision,
            summary: parsed.fetch(:summary),
            source_message_ids: parsed.fetch(:source_message_ids),
            reason: :consolidation
          )
          state.update!(summary: created.summary, revision: revision)
          created
        end
        state.update!(last_consolidated_message_id: last_message_id)
        generation_run.update!(relationship_consolidated_at: now)
        version
      end
    end

    def mark_without_evidence
      generation_run.update!(relationship_consolidated_at: now)
      Result.new(version: nil, error_code: nil)
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
