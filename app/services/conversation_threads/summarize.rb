module ConversationThreads
  class Summarize
    TRANSIENT_ERRORS = %w[timeout rate_limit provider_error].freeze
    Result = Data.define(:version, :error_code) do
      def success? = error_code.nil?
    end

    def self.call(**arguments) = new(**arguments).call

    def initialize(generation_run:, gateway: nil, now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @generation_run = generation_run
      @thread = generation_run.conversation_thread
      @personality = thread.personality
      @gateway = gateway || Ai::ProviderRegistry.gateway_for(generation_run.ai_provider)
      @now = now
      @clock = clock
    end

    def call
      existing = generation_run.thread_summary_version
      return Result.new(version: existing, error_code: nil) if existing
      return Result.new(version: nil, error_code: nil) unless valid_target?

      base_version = thread.summary_versions.order(revision: :desc).first
      messages = messages_through_target
      return Result.new(version: nil, error_code: nil) if messages.empty?

      request = Ai::Request.call(
        user: personality.user, personality: personality, purpose: :thread_summary,
        model: personality.utility_model,
        input: Summary::Prompt.call(previous_summary: thread.summary, messages: messages),
        response_schema: Ai::GroundedSummarySchema::RESPONSE_SCHEMA,
        temperature: 0.1, max_output_tokens: 2_500, gateway: gateway,
        provider: generation_run.ai_provider, now: now, clock: clock
      )
      return request_failure(request) unless request.success?

      parsed = Ai::GroundedSummarySchema.parse(
        text: request.response.text, allowed_message_ids: messages.map(&:id)
      )
      version = persist!(parsed, request.model_call, base_version)
      Result.new(version: version, error_code: nil)
    rescue Ai::GroundedSummarySchema::InvalidOutput
      Result.new(version: nil, error_code: "invalid_output")
    end

    private

    attr_reader :generation_run, :thread, :personality, :gateway, :now, :clock

    def valid_target?
      generation_run.completed? && generation_run.assistant_message&.completed?
    end

    def messages_through_target
      relation = thread.messages.completed.where("position <= ?", generation_run.assistant_message.position)
      if thread.summary_through_message
        relation = relation.where("position > ?", thread.summary_through_message.position)
      end
      relation.reorder(position: :asc).to_a
    end

    def persist!(parsed, model_call, base_version)
      thread.with_lock do
        return generation_run.reload.thread_summary_version if generation_run.thread_summary_version
        current_version = thread.summary_versions.order(revision: :desc).first
        if current_version&.id != base_version&.id
          raise Ai::RetryableContextUpdateError.new(generation_run_id: generation_run.id, error_code: "stale_context")
        end

        version = thread.summary_versions.create!(
          generation_run: generation_run,
          through_message: generation_run.assistant_message,
          previous_version: current_version,
          model_call: model_call,
          revision: current_version ? current_version.revision + 1 : 1,
          summary: parsed.fetch(:summary),
          source_message_ids: parsed.fetch(:source_message_ids)
        )
        thread.update!(summary: version.summary, summary_through_message: version.through_message)
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
  end
end
