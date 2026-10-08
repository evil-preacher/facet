module Operations
  class ModelMetrics
    WINDOW = 24.hours

    def self.call(now: Time.current)
      since = now - WINDOW
      groups = ModelCall.where(created_at: since..).group(:provider, :model, :purpose)
        .pluck(
          :provider, :model, :purpose,
          Arel.sql("COUNT(*)"),
          Arel.sql("COUNT(*) FILTER (WHERE model_calls.status = 'failed')"),
          Arel.sql("AVG(model_calls.latency_ms)"),
          Arel.sql("COALESCE(SUM(model_calls.input_tokens), 0)"),
          Arel.sql("COALESCE(SUM(model_calls.cached_input_tokens), 0)"),
          Arel.sql("COALESCE(SUM(model_calls.output_tokens), 0)"),
          Arel.sql("COALESCE(SUM(model_calls.cost_microusd), 0)")
        )
      first_token_by_model = ModelCall.joins(:generation_run).where(created_at: since..)
        .where("generation_runs.prompt_manifest ? 'first_token_latency_ms'")
        .group(:provider, :model, :purpose)
        .pluck(:provider, :model, :purpose,
               Arel.sql("AVG((generation_runs.prompt_manifest->>'first_token_latency_ms')::numeric)"))
        .to_h { |provider, model, purpose, average| [ [ provider, model, purpose ], average ] }

      {
        window_start: since.iso8601,
        window_end: now.iso8601,
        model_calls: groups.map do |provider, model, purpose, count, errors, latency, input, cached, output, cost|
          {
            provider: provider, model: model, purpose: purpose, calls: count,
            errors: errors, average_latency_ms: latency&.round,
            average_first_token_ms: first_token_by_model[[ provider, model, purpose ]]&.round,
            input_tokens: input.to_i, cached_input_tokens: cached.to_i, output_tokens: output.to_i,
            cached_ratio: input.to_i.positive? ? (cached.to_f / input).round(4) : 0.0,
            cost_microusd: cost.to_i
          }
        end,
        initiative_decisions: InitiativeAttempt.where(decided_at: since..).group(:decision).count,
        initiative_completed: InitiativeAttempt.completed.where(completed_at: since..).count,
        initiative_email_deliveries: InitiativeEmailDelivery.where(created_at: since..).group(:status).count,
        queues: Sidekiq::Queue.all.to_h do |queue|
          [ queue.name, { depth: queue.size, latency_seconds: queue.latency.round(3) } ]
        end,
        outbox_pending: OutboxEvent.pending.count
      }
    end
  end
end
