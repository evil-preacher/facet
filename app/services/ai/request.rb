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
      StoppedError => [ "stopped", "Generation stopped" ],
      ValidationError => [ "validation_error", "Model request is invalid" ],
      BudgetExceededError => [ "budget_exceeded", "Spending limit exceeded" ],
      ProviderError => [ "provider_error", "Model provider request failed" ]
    }.freeze

    def self.call(**arguments, &block)
      new(**arguments).call(&block)
    end

    def initialize(user:, personality:, purpose:, model:, input:, prompt_cache_key: nil,
                   response_schema: nil, temperature: nil, max_output_tokens: nil, generation_run: nil,
                   stream: false, finalize_generation_run: true, model_role: nil,
                   gateway: Gateway.default, provider: Rails.configuration.x.ai.provider, now: Time.current,
                   clock: -> { Process.clock_gettime(Process::CLOCK_MONOTONIC) })
      @user = user
      @personality = personality
      @generation_run = generation_run
      @purpose = purpose
      @model_role = model_role
      @model = model
      @input = input
      @prompt_cache_key = prompt_cache_key
      @response_schema = response_schema
      @temperature = temperature
      @max_output_tokens = max_output_tokens || SpendingBudget::DEFAULT_MAX_OUTPUT_TOKENS
      @stream = stream
      @finalize_generation_run = finalize_generation_run
      @gateway = gateway
      @provider = provider
      @now = now
      @clock = clock
      @model = configured_model if ModelPrice.current_for(provider: @provider, model: @model, at: @now).nil?
    end

    def call(&on_delta)
      return Result.new(model_call: nil, response: nil, error_code: "invalid_context") unless valid_context?

      guard_code = claim_generation_run
      return Result.new(model_call: nil, response: nil, error_code: guard_code) if guard_code

      @price = ModelPrice.current_for(provider: @provider, model: @model, at: @now)
      raise PriceNotFoundError unless @price

      @model_call = SpendingBudget.reserve!(
        user: @user, personality: @personality, generation_run: @generation_run,
        purpose: @purpose, provider: @provider, model: @model, price: @price,
        input: @input, response_schema: @response_schema,
        max_output_tokens: @max_output_tokens, now: @now
      )

      started = @clock.call
      response = provider_response do |delta|
        @first_token_latency_ms ||= elapsed_ms(started) if delta.to_s.present?
        on_delta&.call(delta)
      end
      complete!(response, elapsed_ms(started))
      Result.new(model_call: @model_call, response: response, error_code: nil)
    rescue Error => error
      if error.is_a?(BudgetExceededError)
        Operations::Telemetry.emit("budget_rejection", purpose: @purpose, provider: @provider,
                                   model: @model, generation_run_id: @generation_run&.id,
                                   error_code: "budget_exceeded")
      end
      if @model_call&.persisted?
        fail!(error)
      elsif finalize_generation_run?
        @generation_run.update!(status: :failed, error_code: error_details(error).first,
                                error_message: error_details(error).last, completed_at: @now)
      end
      Result.new(model_call: @model_call, response: nil, error_code: error_details(error).first)
    end

    private

    def configured_model
      role = @model_role.to_s == "conversation" || @purpose.to_s == "conversation" ? "CONVERSATION" : "UTILITY"
      case @provider.to_s
      when "mistral"
        ENV.fetch("MISTRAL_#{role}_MODEL", role == "CONVERSATION" ? "mistral-large-2512" : "mistral-small-latest")
      when "openai"
        ENV.fetch("OPENAI_#{role}_MODEL", role == "CONVERSATION" ? "gpt-4o-2024-11-20" : "gpt-4o-mini")
      else
        @model
      end
    end

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
        return "already_failed" if @generation_run.failed?
        return "stopped" if @generation_run.stopped?

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
          response_model: response.model,
          status: :completed,
          input_tokens: usage.input_tokens,
          cached_input_tokens: usage.cached_input_tokens,
          output_tokens: usage.output_tokens,
          cost_microusd: cost,
          reserved_cost_microusd: 0,
          reservation_expires_at: nil,
          pricing_version: @price.version,
          latency_ms: latency_ms,
          completed_at: @now
        )
        @generation_run&.update!(status: :completed, completed_at: @now) if finalize_generation_run?
        record_first_token_latency!
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
        reserved_cost_microusd: 0,
        reservation_expires_at: nil,
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
        ) if finalize_generation_run?
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

    def record_first_token_latency!
      return unless @generation_run && @first_token_latency_ms

      @generation_run.update_column(
        :prompt_manifest,
        @generation_run.prompt_manifest.merge("first_token_latency_ms" => @first_token_latency_ms)
      )
    end

    def error_details(error)
      ERROR_DETAILS.fetch(error.class, ERROR_DETAILS.fetch(ProviderError))
    end

    def provider_response(&on_delta)
      arguments = {
        model: @model,
        input: @input,
        prompt_cache_key: @prompt_cache_key
      }
      arguments[:response_schema] = @response_schema if @response_schema
      arguments[:temperature] = @temperature unless @temperature.nil?
      arguments[:max_output_tokens] = @max_output_tokens unless @max_output_tokens.nil?
      arguments[:max_output_tokens] = @max_output_tokens
      return @gateway.response(**arguments) unless @stream

      @gateway.stream_response(**arguments, &on_delta)
    end

    def finalize_generation_run?
      @finalize_generation_run && @generation_run
    end
  end
end
