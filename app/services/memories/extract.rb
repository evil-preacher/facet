module Memories
  class Extract
    Result = Data.define(:status, :error_code, :memories)
    TRANSIENT_ERROR_CODES = %w[timeout rate_limit provider_error].freeze
    STALE_RUNNING_AFTER = 15.minutes

    def self.call(**arguments)
      new(**arguments).call
    end

    def self.mark_terminal!(memory_extraction_id:, error_code:)
      extraction = MemoryExtraction.find_by(id: memory_extraction_id)
      return unless extraction

      extraction.with_lock do
        next if extraction.completed? || extraction.skipped?

        extraction.update!(
          status: :failed,
          started_at: nil,
          completed_at: Time.current,
          error_code: error_code,
          error_message: "Memory extraction failed after retries"
        )
      end
    end

    def initialize(extraction:, gateway: nil, now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @extraction = extraction
      @personality = extraction.personality
      @gateway = gateway || Ai::ProviderRegistry.gateway_for(extraction.generation_run.ai_provider)
      @now = now
      @clock = clock
    end

    def call
      return Result.new(status: :skipped, error_code: nil, memories: []) unless claim!

      request = Ai::Request.call(
        user: personality.user,
        personality: personality,
        purpose: :memory_extraction,
        model: personality.utility_model,
        input: Extraction::Prompt.call(
          extraction: extraction,
          active_memories: active_memories,
          now: now
        ),
        response_schema: Extraction::Schema::RESPONSE_SCHEMA,
        temperature: 0.1,
        max_output_tokens: 2_500,
        gateway: gateway,
        provider: extraction.generation_run.ai_provider,
        now: now,
        clock: clock
      )
      return handle_request_failure(request) unless request.success?

      candidates = Extraction::Schema.parse(
        text: request.response.text,
        allowed_message_ids: source_message_ids,
        allowed_memory_ids: active_memories.map(&:id)
      )
      memories = []
      MemoryExtraction.transaction do
        memories = ApplyCandidates.call(extraction: extraction, candidates: candidates)
        extraction.update!(
          status: :completed,
          model_call: request.model_call,
          started_at: nil,
          completed_at: now,
          error_code: nil,
          error_message: nil
        )
      end
      Result.new(status: :completed, error_code: nil, memories: memories)
    rescue Extraction::Schema::InvalidOutput
      fail_current!(code: "invalid_output", message: "Memory model returned invalid structured output")
      Result.new(status: :failed, error_code: "invalid_output", memories: [])
    rescue Ai::RetryableMemoryExtractionError
      raise
    rescue StandardError => error
      Rails.logger.error(
        "Unexpected memory extraction failure memory_extraction_id=#{extraction.id} " \
        "error=#{error.class.name}"
      )
      retryable_failure!("unexpected_error")
    end

    private

    attr_reader :extraction, :personality, :gateway, :now, :clock

    def claim!
      extraction.with_lock do
        return false if extraction.completed? || extraction.skipped?
        if extraction.running? && extraction.started_at && extraction.started_at > now - STALE_RUNNING_AFTER
          return false
        end
        unless personality.automatic_memory_enabled? && extraction.generation_run.completed?
          extraction.update!(status: :skipped, completed_at: now)
          return false
        end

        extraction.update!(
          status: :running,
          attempts_count: extraction.attempts_count + 1,
          started_at: now,
          completed_at: nil,
          error_code: nil,
          error_message: nil
        )
      end
      true
    end

    def handle_request_failure(request)
      if TRANSIENT_ERROR_CODES.include?(request.error_code)
        retryable_failure!(request.error_code)
      else
        fail_current!(code: request.error_code, message: "Memory extraction request failed")
        Result.new(status: :failed, error_code: request.error_code, memories: [])
      end
    end

    def retryable_failure!(code)
      fail_current!(code: code, message: "Memory extraction will be retried", status: :pending)
      raise Ai::RetryableMemoryExtractionError.new(
        memory_extraction_id: extraction.id,
        error_code: code
      )
    end

    def fail_current!(code:, message:, status: :failed)
      extraction.with_lock do
        next if extraction.completed? || extraction.skipped?

        extraction.update!(
          status: status,
          started_at: nil,
          completed_at: status == :failed ? now : nil,
          error_code: code,
          error_message: message
        )
      end
    end

    def source_message_ids
      Extraction::Prompt.source_messages(extraction: extraction).map(&:id)
    end

    def active_memories
      @active_memories ||= personality.memories.active
        .order(importance: :desc, updated_at: :desc)
        .limit(100)
        .to_a
    end
  end
end
