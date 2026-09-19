module Ai
  class Request
    Result = Data.define(:model_call, :response, :error_code) do
      def success?
        error_code.nil?
      end
    end

    ERROR_DETAILS = {
      TimeoutError => [ "timeout", "Model request timed out" ],
      RateLimitError => [ "rate_limit", "Model provider rate limit exceeded" ],
      MalformedResponseError => [ "malformed_response", "Model provider returned an invalid response" ],
      PriceNotFoundError => [ "price_not_found", "Model price is not configured" ],
      ProviderError => [ "provider_error", "Model provider request failed" ]
    }.freeze

    def self.call(**arguments)
      new(**arguments).call
    end

    def initialize(user:, personality:, purpose:, model:, input:, prompt_cache_key: nil, generation_run: nil,
                   gateway: Gateway.default, provider: "openai", now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @user = user
      @personality = personality
      @generation_run = generation_run
      @purpose = purpose
      @model = model
      @input = input
      @prompt_cache_key = prompt_cache_key
      @gateway = gateway
      @provider = provider
      @now = now
      @clock = clock
    end

    def call
      return Result.new(model_call: nil, response: nil, error_code: "invalid_context") unless valid_context?

      guard_code = claim_generation_run
      return Result.new(model_call: nil, response: nil, error_code: guard_code) if guard_code

      @model_call = ModelCall.create!(
        user: @user,
        personality: @personality,
        generation_run: @generation_run,
        purpose: @purpose,
        provider: @provider,
        model: @model,
        status: :pending
      )
      @price = ModelPrice.current_for(provider: @provider, model: @model, at: @now)
      raise PriceNotFoundError unless @price

      started = @clock.call
      response = @gateway.response(
        model: @model,
        input: @input,
        prompt_cache_key: @prompt_cache_key
      )
      complete!(response, elapsed_ms(started))
      Result.new(model_call: @model_call, response: response, error_code: nil)
    rescue Error => error
      fail!(error) if @model_call&.persisted?
      Result.new(model_call: @model_call, response: nil, error_code: error_details(error).first)
    end

    private

    def valid_context?
      return false unless @user && @personality&.user_id == @user.id
      return true unless @generation_run

      @generation_run.conversation_thread.personality_id == @personality.id
    end

    def claim_generation_run
      return unless @generation_run

      @generation_run.with_lock do
        return "already_completed" if @generation_run.completed?
        return "already_running" if @generation_run.running?

        @generation_run.update!(
          status: :running,
          attempts_count: @generation_run.attempts_count + 1,
          started_at: @now,
          completed_at: nil,
          error_code: nil,
          error_message: nil
        )
      end
      nil
    end

    def complete!(response, latency_ms)
      usage = response.usage
      cost = CostCalculator.call(
        price: @price,
        input_tokens: usage.input_tokens,
        cached_input_tokens: usage.cached_input_tokens,
        output_tokens: usage.output_tokens
      )

      ModelCall.transaction do
        @model_call.update!(
          provider_request_id: response.request_id,
          status: :completed,
          input_tokens: usage.input_tokens,
          cached_input_tokens: usage.cached_input_tokens,
          output_tokens: usage.output_tokens,
          cost_microusd: cost,
          pricing_version: @price.version,
          latency_ms: latency_ms,
          completed_at: @now
        )
        @generation_run&.update!(status: :completed, completed_at: @now)
      end
    end

    def fail!(error)
      code, safe_message = error_details(error)
      attributes = {
        provider_request_id: error.request_id,
        status: :failed,
        error_class: error.class.name,
        error_code: code,
        error_message: safe_message,
        completed_at: @now
      }
      add_partial_usage!(attributes, error.usage) if error.usage && @price

      ModelCall.transaction do
        @model_call.update!(attributes)
        @generation_run&.update!(
          status: :failed,
          error_code: code,
          error_message: safe_message,
          completed_at: @now
        )
      end
    end

    def add_partial_usage!(attributes, usage)
      attributes.merge!(
        input_tokens: usage.input_tokens,
        cached_input_tokens: usage.cached_input_tokens,
        output_tokens: usage.output_tokens,
        cost_microusd: CostCalculator.call(
          price: @price,
          input_tokens: usage.input_tokens,
          cached_input_tokens: usage.cached_input_tokens,
          output_tokens: usage.output_tokens
        ),
        pricing_version: @price.version
      )
    end

    def elapsed_ms(started)
      ((@clock.call - started) * 1000).round.clamp(0, 2_147_483_647)
    end

    def error_details(error)
      ERROR_DETAILS.fetch(error.class, ERROR_DETAILS.fetch(ProviderError))
    end
  end
end
